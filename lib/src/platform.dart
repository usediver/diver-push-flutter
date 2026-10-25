import 'platform_io.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    as detected;

/// The platforms Diver Push targets a campaign at. The wire name is the
/// enum's name.
enum DiverPushPlatform {
  ios,
  android,
  web,
  macos,
  windows;

  /// The platform this code is running on.
  ///
  /// Resolved from the compiled-for platform rather than passed in, so an
  /// app with one code path for every platform registers the right one.
  /// Linux has no push transport Diver sends to, so it is not an answer;
  /// pass a platform explicitly if you register from somewhere unusual.
  static DiverPushPlatform get current => detected.currentPlatform();
}
