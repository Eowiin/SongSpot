import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/main.dart';

/// Leaving the foreground drops the focus and stops the snippet. `inactive`
/// does not mean that on every platform, and getting it wrong on Android took
/// the focus off the login fields as soon as the autofill sheet opened over
/// them — the keyboard closed on every tap and signing in was impossible.

void main() {
  group('leavesForeground', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('ignores the resumed state everywhere', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          leavesForeground(AppLifecycleState.resumed),
          isFalse,
          reason: '$platform',
        );
      }
    });

    test('sits out inactive on Android, where it is a lost window focus', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(leavesForeground(AppLifecycleState.inactive), isFalse);
    });

    test('acts on inactive on iOS, where it is the switcher or a call', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(leavesForeground(AppLifecycleState.inactive), isTrue);
    });

    test('still acts once Android goes away for real', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // Android synthesises `hidden` before `paused`, so sitting `inactive` out
      // costs nothing: a genuine background is still caught here.
      expect(leavesForeground(AppLifecycleState.hidden), isTrue);
      expect(leavesForeground(AppLifecycleState.paused), isTrue);
      expect(leavesForeground(AppLifecycleState.detached), isTrue);
    });
  });
}
