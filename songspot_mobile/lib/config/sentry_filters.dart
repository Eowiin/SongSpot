import 'package:sentry_flutter/sentry_flutter.dart';

/// Whether an event is noise we deliberately keep out of Sentry.
///
/// Everything dropped here comes from code we do not own and is reported as an
/// unhandled error, so it marks the session as crashed. Left alone it drags the
/// crash-free rate down and buries the issues that are actually ours.
bool isDroppedSentryEvent(SentryEvent event) {
  final throwable = event.throwable?.toString() ?? '';
  // google_fonts fetches TTFs over the network on first use; on a
  // dropped/offline connection it throws unhandled, which is a device
  // connectivity issue rather than an app bug.
  if (throwable.contains('Failed to load font with url')) return true;
  return _isFloatingCursorRace(event, throwable);
}

/// The iOS floating-cursor race inside Flutter's own text input plumbing.
///
/// Dragging the caret with the space bar makes the engine stream
/// `TextInputClient.updateFloatingCursor` messages. If the field gives up its
/// connection while one is still in flight — the round advances, the app leaves
/// the foreground, a tap outside moves the focus — the framework handler
/// dereferences a connection that is already null, at
/// `_currentConnection!._client.updateFloatingCursor(...)` in
/// `services/text_input.dart`. No code of ours sits on that path, and the app
/// keeps running; only the report is left behind.
///
/// Matched narrowly on purpose. The same null check guards every other
/// `TextInputClient.*` call, and some of those — `performAction`, say — do run
/// our callbacks, where a null check failure would be a real bug worth seeing.
bool _isFloatingCursorRace(SentryEvent event, String throwable) {
  if (!throwable.contains('Null check operator used on a null value')) {
    return false;
  }
  final details = event.contexts['flutter_error_details'];
  if (details is! Map) return false;
  if (details['library'] != 'services library') return false;
  final context = details['context'];
  return context is String &&
      context.contains('TextInputClient.updateFloatingCursor');
}
