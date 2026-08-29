import 'package:web/web.dart' as web;

void dismissPlatformBootSplash() {
  final boot = web.document.getElementById('boot');
  if (boot == null) return;
  boot.classList.add('boot--done');
  // Matches the 250ms opacity transition in index.html.
  Future<void>.delayed(const Duration(milliseconds: 300), () => boot.remove());
}
