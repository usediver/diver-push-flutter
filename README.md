# diver_push

Register your app's push tokens and report notification opens with
[Diver Push](https://push.usediver.com), so the campaigns you send from the
console reach your users and you can see who opened them.

The package does not touch Firebase. Your app keeps its own
`firebase_messaging` setup — permissions, the token, delivery — and this is
the few calls that tell Diver about it. Pure Dart, one dependency
(`package:http`), works in Flutter on every platform and in plain Dart.

## Setup

1. In the push console, open your app's **Device tokens** card and **Create
   app key**. It starts with `pk_` and is safe to ship inside your build:
   it can register tokens and report opens for this one app, and nothing
   else. (Never ship a `dk_` CI key; the constructor refuses one.)
2. Add the package and construct a client once, with the organization and
   app ids from the console's URL:

```dart
import 'package:diver_push/diver_push.dart';

final diverPush = DiverPush(
  appKey: 'pk_…',
  orgId: '<organization id>',
  appId: '<app id>',
  // baseUrl: Uri.parse('https://api-dev.usediver.com'), // staging
);
```

## Register the token

Once you have an FCM token, register it under your own id for the user or
install — the `externalId` — and the tags campaigns target. Register again
whenever FCM refreshes the token; the same `externalId` replaces its entry.

```dart
final messaging = FirebaseMessaging.instance;

Future<void> registerWithDiver(String userId) async {
  final token = await messaging.getToken();
  if (token != null) {
    await diverPush.register(externalId: userId, token: token, tags: ['pro']);
  }
}

messaging.onTokenRefresh.listen((token) {
  diverPush.register(externalId: currentUserId, token: token, tags: ['pro']);
});
```

On sign-out, forget it, so the next campaign does not land on a device
nobody is signed in on:

```dart
await diverPush.unregister(userId);
```

## Report the tap

Hand both of Firebase's tap paths to `handleTap`: the one for a tap that
brought a running app forward, and the one for a tap that launched it. It
answers `null` for anything that is not a Diver campaign, so your other
notifications fall through untouched; otherwise it reports the open and
answers the link the campaign carried, for you to open.

```dart
Future<void> onTap(RemoteMessage message) async {
  final uri = await diverPush.handleTap(message.data, externalId: currentUserId);
  if (uri != null) openDeeplink(uri);
}

FirebaseMessaging.onMessageOpenedApp.listen(onTap);
final launchedBy = await messaging.getInitialMessage();
if (launchedBy != null) await onTap(launchedBy);
```

Reporting is best effort: the user is waiting on the link, so a report that
fails (offline, mostly) is handed to `onError` and the link is still
answered. One open is counted per recipient per campaign, so a second tap
or a retry changes nothing.

## What is sent

Three routes on the Diver API, each with `Authorization: Bearer pk_…`:

| Call | Route |
| --- | --- |
| `register` | `POST /organizations/{org}/apps/{app}/push/tokens` with one `{externalId, token, platform, tags}` entry |
| `unregister` | `DELETE …/push/tokens/{externalId}` |
| `reportOpen` / `handleTap` | `POST …/push/campaigns/{campaignId}/opens` with `{externalId}` |

`platform` is detected from the build (`ios`, `android`, `web`, `macos`,
`windows`); pass one to `register` from anywhere else. A refusal surfaces as
a `DiverPushException` carrying the server's own sentence.
