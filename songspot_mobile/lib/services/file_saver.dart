import 'dart:typed_data';

import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

/// Hands [bytes] to the user as a file named [fileName].
///
/// On mobile/desktop this writes a temp file and opens the native share sheet.
/// On web it triggers a browser download — there is no filesystem to share from.
Future<void> saveBytesAsFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) => savePlatformBytesAsFile(
  bytes: bytes,
  fileName: fileName,
  mimeType: mimeType,
  subject: subject,
);
