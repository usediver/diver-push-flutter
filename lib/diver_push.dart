/// Diver Push for Dart and Flutter: register this install's push token and
/// report the notifications its user taps, so campaigns sent from
/// push.usediver.com reach them and can be measured.
///
/// This package does not touch Firebase. Your app keeps its own
/// `firebase_messaging` (or any other) setup for permissions, tokens and
/// delivery; this is the few calls that tell Diver about them. See the
/// README for the wiring.
library;

export 'src/campaign_tap.dart';
export 'src/diver_push.dart';
export 'src/exception.dart';
export 'src/platform.dart';
