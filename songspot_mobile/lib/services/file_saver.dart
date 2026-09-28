import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

/// Hands [bytes] to the user as a file named [fileName].
///
/// On mobile/desktop this writes a temp file and opens the native share sheet.
/// On web it triggers a browser download — there is no filesystem to share from.
///
/// [origin] is where the share sheet anchors, in global coordinates. iOS
/// refuses to present it without one on iPad, so pass the tapped widget's rect.
Future<void> saveBytesAsFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
  Rect? origin,
}) => savePlatformBytesAsFile(
  bytes: bytes,
  fileName: fileName,
  mimeType: mimeType,
  subject: subject,
  origin: origin,
);
