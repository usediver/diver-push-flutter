import 'dart:convert';

import 'package:http/http.dart' as http;

import 'campaign_tap.dart';
import 'exception.dart';
import 'platform.dart';

/// The Diver Push client for one app.
///
/// Three calls, over the app's public key: [register] a token, [unregister]
/// it, and [reportOpen] a tap. [handleTap] wraps the last one for the
/// notification-tap handlers Firebase gives you.
///
/// The key is public on purpose — it ships inside your build — and can do
/// nothing but these three things for this one app. Keep your `dk_` CI keys
/// out of the app; the constructor refuses one.
class DiverPush {
  DiverPush({
    required this.appKey,
    required this.orgId,
    required this.appId,
    Uri? baseUrl,
    http.Client? client,
  }) : baseUrl = baseUrl ?? defaultBaseUrl,
       _client = client ?? http.Client() {
    if (!appKey.startsWith('pk_')) {
      throw ArgumentError.value(
        appKey.length > 6 ? '${appKey.substring(0, 6)}…' : appKey,
        'appKey',
        'Diver Push takes the app key (pk_…) minted in the push console. '
            'A CI key (dk_…) is a server secret and must not ship in an app.',
      );
    }
  }

  /// The deployed Diver API. Point [DiverPush.new] at `api-dev.usediver.com`
  /// for the staging stack.
  static final Uri defaultBaseUrl = Uri.parse('https://api.usediver.com');

  final String appKey;
  final String orgId;
  final String appId;
  final Uri baseUrl;
  final http.Client _client;

  Uri _push(String path) =>
      baseUrl.resolve('/organizations/$orgId/apps/$appId/push$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $appKey',
    'Content-Type': 'application/json',
  };

  /// Registers this install's push [token] under [externalId]: your own id
  /// for the user or the install, and what you report opens with later.
  ///
  /// Call it once you hold a token, and again every time FCM refreshes it
  /// (`FirebaseMessaging.onTokenRefresh`): the same [externalId] replaces
  /// its entry, so re-registering is always safe. [tags] are what campaigns
  /// target (`pro`, `trial`, `da`); a tag cannot contain a comma.
  Future<void> register({
    required String externalId,
    required String token,
    DiverPushPlatform? platform,
    List<String> tags = const [],
  }) async {
    final response = await _client.post(
      _push('/tokens'),
      headers: _headers,
      body: jsonEncode({
        'tokens': [
          {
            'externalId': externalId,
            'token': token,
            'platform': (platform ?? DiverPushPlatform.current).name,
            'tags': tags,
          },
        ],
      }),
    );
    _check(response);
  }

  /// Forgets [externalId]'s token, so the next campaign does not reach a
  /// device nobody is signed in on. Call it on sign-out. Forgetting a token
  /// that was never registered is not an error.
  Future<void> unregister(String externalId) async {
    final response = await _client.delete(
      _push('/tokens/$externalId'),
      headers: _headers,
    );
    if (response.statusCode == 404) return;
    _check(response);
  }

  /// Reports that [externalId] tapped the notification for [campaignId].
  ///
  /// Counted once per recipient per campaign, so reporting twice — a second
  /// tap, a retried call — changes nothing. Throws [DiverPushException] with
  /// a 409 for a campaign that has not been sent, which only a forged
  /// notification could produce.
  Future<void> reportOpen({
    required String campaignId,
    required String externalId,
  }) async {
    final response = await _client.post(
      _push('/campaigns/$campaignId/opens'),
      headers: _headers,
      body: jsonEncode({'externalId': externalId}),
    );
    _check(response);
  }

  /// The tap handler, for `FirebaseMessaging.onMessageOpenedApp` and the
  /// message `getInitialMessage()` answers: hand it `message.data`.
  ///
  /// Answers null when the notification is not a Diver campaign, so your
  /// other notifications fall through untouched. Otherwise it reports the
  /// open and answers the link the campaign carried, for you to open — or
  /// null for a campaign that just opens the app.
  ///
  /// Reporting is best effort: the user is waiting on the link, so a report
  /// that fails (offline, mostly) is handed to [onError] and the link is
  /// still answered. Nothing throws out of here.
  Future<Uri?> handleTap(
    Map<String, Object?> data, {
    required String externalId,
    void Function(Object error)? onError,
  }) async {
    final tap = DiverCampaignTap.parse(data);
    if (tap == null) return null;
    try {
      await reportOpen(campaignId: tap.campaignId, externalId: externalId);
    } on Object catch (e) {
      onError?.call(e);
    }
    return tap.uri;
  }

  /// Closes the underlying HTTP client. Only needed if you created the
  /// [DiverPush] for a short job; an app keeps one for its lifetime.
  void close() => _client.close();

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = response.body.trim();
    throw DiverPushException(
      response.statusCode,
      body.isNotEmpty ? body : response.reasonPhrase ?? 'Request failed',
    );
  }
}
