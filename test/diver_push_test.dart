import 'dart:convert';
import 'dart:io' show Platform;

import 'package:diver_push/diver_push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Answers [status] with [body] and keeps every request it saw.
class Recording {
  final requests = <http.Request>[];
  int status;
  String body;

  Recording({this.status = 204, this.body = ''});

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return http.Response(body, status);
  });

  http.Request get only => requests.single;
  Map<String, Object?> get sentJson =>
      jsonDecode(only.body) as Map<String, Object?>;
}

DiverPush pushWith(Recording server, {String key = 'pk_test'}) => DiverPush(
  appKey: key,
  orgId: 'org-1',
  appId: 'app-1',
  client: server.client,
);

void main() {
  group('the key', () {
    test('must be the public one; a CI secret does not ship in an app', () {
      expect(
        () => pushWith(Recording(), key: 'dk_secret'),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => pushWith(Recording(), key: 'pk_fine'), returnsNormally);
    });

    test('is presented as a bearer token on every call', () async {
      final server = Recording();
      await pushWith(server).unregister('u1');
      expect(server.only.headers['Authorization'], 'Bearer pk_test');
    });
  });

  group('register', () {
    test('posts one token entry to the app, in the server\'s shape', () async {
      final server = Recording();
      await pushWith(server).register(
        externalId: 'u1',
        token: 'fcm-token',
        platform: DiverPushPlatform.ios,
        tags: ['pro', 'da'],
      );
      final request = server.only;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.usediver.com/organizations/org-1/apps/app-1/push/tokens',
      );
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(server.sentJson, {
        'tokens': [
          {
            'externalId': 'u1',
            'token': 'fcm-token',
            'platform': 'ios',
            'tags': ['pro', 'da'],
          },
        ],
      });
    });

    test('names the running platform when none is given', () async {
      final server = Recording();
      final registering = pushWith(
        server,
      ).register(externalId: 'u1', token: 't');
      if (Platform.isLinux) {
        // Diver sends to no Linux transport, so there is no name to send;
        // better refused here than registered as something it is not.
        await expectLater(registering, throwsUnsupportedError);
        expect(server.requests, isEmpty);
        return;
      }
      await registering;
      final entry =
          (server.sentJson['tokens'] as List<Object?>).single
              as Map<String, Object?>;
      expect(
        DiverPushPlatform.values.map((p) => p.name),
        contains(entry['platform']),
      );
    });

    test('honours another base URL', () async {
      final server = Recording();
      final push = DiverPush(
        appKey: 'pk_test',
        orgId: 'o',
        appId: 'a',
        baseUrl: Uri.parse('https://api-dev.usediver.com'),
        client: server.client,
      );
      await push.register(
        externalId: 'u1',
        token: 't',
        platform: DiverPushPlatform.android,
      );
      expect(server.only.url.host, 'api-dev.usediver.com');
    });

    test(
      'surfaces the server\'s refusal as an exception with its sentence',
      () async {
        final server = Recording(
          status: 403,
          body: 'An app key can only register push tokens and report opens.',
        );
        expect(
          () => pushWith(server).register(
            externalId: 'u1',
            token: 't',
            platform: DiverPushPlatform.ios,
          ),
          throwsA(
            isA<DiverPushException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.message, 'message', contains('app key')),
          ),
        );
      },
    );
  });

  group('unregister', () {
    test('deletes the token by external id', () async {
      final server = Recording();
      await pushWith(server).unregister('user one');
      expect(server.only.method, 'DELETE');
      expect(
        server.only.url.path,
        '/organizations/org-1/apps/app-1/push/tokens/user%20one',
      );
    });

    test('is quiet about a token that was never registered', () async {
      final server = Recording(status: 404, body: 'No such token');
      await expectLater(pushWith(server).unregister('ghost'), completes);
    });
  });

  group('reportOpen', () {
    test('posts the external id to the campaign', () async {
      final server = Recording();
      await pushWith(server).reportOpen(campaignId: 'c1', externalId: 'u1');
      expect(
        server.only.url.path,
        '/organizations/org-1/apps/app-1/push/campaigns/c1/opens',
      );
      expect(server.sentJson, {'externalId': 'u1'});
    });

    test('throws for a campaign that was never sent', () async {
      final server = Recording(
        status: 409,
        body: 'That campaign has not been sent',
      );
      expect(
        () => pushWith(server).reportOpen(campaignId: 'c1', externalId: 'u1'),
        throwsA(
          isA<DiverPushException>().having(
            (e) => e.statusCode,
            'statusCode',
            409,
          ),
        ),
      );
    });
  });

  group('DiverCampaignTap.parse', () {
    test('reads the campaign and its link', () {
      final tap = DiverCampaignTap.parse({
        'campaignId': 'c1',
        'uri': 'shop://sale',
      });
      expect(tap?.campaignId, 'c1');
      expect(tap?.uri, Uri.parse('shop://sale'));
    });

    test('is null for a notification that is not a campaign', () {
      expect(DiverCampaignTap.parse({'uri': 'shop://sale'}), isNull);
      expect(DiverCampaignTap.parse({'campaignId': ''}), isNull);
      expect(DiverCampaignTap.parse({}), isNull);
      // The link-delivery protocol Diver's own app speaks is not a campaign either.
      expect(
        DiverCampaignTap.parse({'version': '1', 'uri': 'diver://x'}),
        isNull,
      );
    });

    test('keeps the campaign when the link is missing or unreadable', () {
      expect(DiverCampaignTap.parse({'campaignId': 'c1'})?.uri, isNull);
      expect(
        DiverCampaignTap.parse({'campaignId': 'c1', 'uri': ''})?.uri,
        isNull,
      );
      expect(
        DiverCampaignTap.parse({'campaignId': 'c1', 'uri': 42})?.uri,
        isNull,
      );
    });
  });

  group('handleTap', () {
    test('reports the open and answers the link', () async {
      final server = Recording();
      final uri = await pushWith(
        server,
      ).handleTap({'campaignId': 'c1', 'uri': 'shop://sale'}, externalId: 'u1');
      expect(uri, Uri.parse('shop://sale'));
      expect(server.only.url.path, endsWith('/campaigns/c1/opens'));
    });

    test('leaves another sender\'s notification alone', () async {
      final server = Recording();
      expect(
        await pushWith(server).handleTap({'foo': 'bar'}, externalId: 'u1'),
        isNull,
      );
      expect(server.requests, isEmpty);
    });

    test('still answers the link when the report fails, and says so', () async {
      final server = Recording(status: 500, body: 'boom');
      Object? seen;
      final uri = await pushWith(server).handleTap(
        {'campaignId': 'c1', 'uri': 'shop://sale'},
        externalId: 'u1',
        onError: (e) => seen = e,
      );
      expect(uri, Uri.parse('shop://sale'));
      expect(seen, isA<DiverPushException>());
    });

    test('answers null for a campaign that just opens the app', () async {
      final server = Recording();
      expect(
        await pushWith(
          server,
        ).handleTap({'campaignId': 'c1'}, externalId: 'u1'),
        isNull,
      );
      expect(server.requests, hasLength(1));
    });
  });
}
