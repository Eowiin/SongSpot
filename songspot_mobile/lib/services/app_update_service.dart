import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/api_config.dart';

/// A store release the installed app has to be updated to.
class RequiredUpdate {
  final String latestVersion;
  final String storeUrl;

  const RequiredUpdate({required this.latestVersion, required this.storeUrl});
}

/// Asks the server which version each store serves, and whether this install
/// is behind it.
///
/// The check fails open: if the server is slow, unreachable or answers
/// something unexpected, the app starts normally. A backend outage must never
/// lock every player out of the app as well.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// Short, because it sits on the launch path: past this the player is let in.
  static const _timeout = Duration(seconds: 4);

  /// The update this install needs, or null when it is current, the platform
  /// is not checked (web, desktop), or the answer could not be obtained.
  Future<RequiredUpdate?> checkRequiredUpdate() async {
    final platform = _platformKey();
    if (platform == null) return null;
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}${ApiConfig.appVersion}'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final release = body[platform];
      if (release is! Map<String, dynamic>) return null;
      final latest = release['latest_version'];
      final storeUrl = release['store_url'];
      if (latest is! String || storeUrl is! String || storeUrl.isEmpty) return null;

      final installed = (await PackageInfo.fromPlatform()).version;
      if (!isOlderVersion(installed, latest)) return null;
      return RequiredUpdate(latestVersion: latest, storeUrl: storeUrl);
    } catch (e) {
      debugPrint('[AppUpdate] check skipped: $e');
      return null;
    }
  }

  static String? _platformKey() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }
}

/// Whether [installed] is an earlier release than [latest].
///
/// Compares the store version name ("2.3.4") part by part, numerically, so
/// 2.10.0 is newer than 2.9.9. The build number ("+57") is ignored: it is
/// counted separately on each platform and says nothing about which release
/// is newer. Anything unparseable is treated as current, so a malformed value
/// can never lock players out.
bool isOlderVersion(String installed, String latest) {
  final a = _parse(installed);
  final b = _parse(latest);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

List<int>? _parse(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}
