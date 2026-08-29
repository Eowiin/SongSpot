import 'boot_splash_io.dart'
    if (dart.library.js_interop) 'boot_splash_web.dart';

/// Dismisses the HTML boot splash painted by `web/index.html`.
///
/// No-op everywhere except the web build, where the splash covers the gap
/// between the page load and Flutter's first frame.
void dismissBootSplash() => dismissPlatformBootSplash();
