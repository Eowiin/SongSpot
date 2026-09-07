import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:songspot_mobile/config/sentry_filters.dart';

/// A genuine `Null check operator used on a null value`, thrown rather than
/// spelled out, so the test keeps matching whatever wording the SDK uses.
Object nullCheckError() {
  try {
    _unwrap(null);
  } catch (error) {
    return error;
  }
  fail('expected the null check to throw');
}

int _unwrap(int? value) => value!;

/// The event `FlutterErrorIntegration` builds: the throwable is wrapped in a
/// mechanism, and the details land in a `flutter_error_details` context whose
/// `context` entry is prefixed with `thrown `.
SentryEvent flutterErrorEvent(
  Object throwable, {
  String? library,
  String? context,
}) {
  return SentryEvent(
    throwable: ThrowableMechanism(
      Mechanism(type: 'FlutterError', handled: false),
      throwable,
    ),
    level: SentryLevel.fatal,
    contexts: Contexts()
      ..['flutter_error_details'] = <String, String>{
        if (context != null) 'context': 'thrown $context',
        if (library != null) 'library': library,
      },
  );
}

void main() {
  group('isDroppedSentryEvent', () {
    test('drops the iOS floating cursor race', () {
      final event = flutterErrorEvent(
        nullCheckError(),
        library: 'services library',
        context: 'during method call TextInputClient.updateFloatingCursor',
      );

      expect(isDroppedSentryEvent(event), isTrue);
    });

    test('keeps a null check failure raised on another text input call', () {
      // `performAction` runs our own onSubmitted handler, so a null check that
      // fails there is a bug of ours and has to stay visible.
      final event = flutterErrorEvent(
        nullCheckError(),
        library: 'services library',
        context: 'during method call TextInputClient.performAction',
      );

      expect(isDroppedSentryEvent(event), isFalse);
    });

    test('keeps a null check failure from our own widgets', () {
      final event = flutterErrorEvent(
        nullCheckError(),
        library: 'widgets library',
        context: 'during a scheduler callback',
      );

      expect(isDroppedSentryEvent(event), isFalse);
    });

    test('keeps an event with no flutter error details', () {
      expect(isDroppedSentryEvent(SentryEvent(throwable: nullCheckError())),
          isFalse);
    });

    test('drops a font that failed to download', () {
      final event = SentryEvent(
        throwable: Exception('Failed to load font with url: https://x/y.ttf'),
      );

      expect(isDroppedSentryEvent(event), isTrue);
    });

    test('keeps an ordinary error', () {
      final event = SentryEvent(throwable: StateError('boom'));

      expect(isDroppedSentryEvent(event), isFalse);
    });
  });
}
