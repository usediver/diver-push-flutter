import 'dart:io' show Platform;

import 'platform.dart';

DiverPushPlatform currentPlatform() {
  if (Platform.isIOS) return DiverPushPlatform.ios;
  if (Platform.isAndroid) return DiverPushPlatform.android;
  if (Platform.isMacOS) return DiverPushPlatform.macos;
  if (Platform.isWindows) return DiverPushPlatform.windows;
  throw UnsupportedError(
    'Diver Push has no platform name for ${Platform.operatingSystem}; '
    'pass one to register() explicitly.',
  );
}
