import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final String htmlUrl;

  UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.htmlUrl,
  });
}

class UpdateService {
  static const String _githubOwner = 'Lucifer-pw';
  static const String _githubRepo = 'LUCIFAX-PFS';
  static const String currentVersion = '1.2.4';

  /// Checks the latest GitHub release and returns [UpdateInfo] if a newer
  /// version is available, or `null` if the app is already up-to-date.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      // Get the current app version at runtime
      final packageInfo = await PackageInfo.fromPlatform();
      final String installedVersion = packageInfo.version;

      final url = Uri.parse(
        'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
      );

      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);

      final request = await httpClient.getUrl(url);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', '$_githubRepo-updater');

      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      httpClient.close();

      final Map<String, dynamic> json = jsonDecode(responseBody);

      // Parse tag_name — strip leading 'v' if present
      String tagName = json['tag_name'] as String? ?? '';
      if (tagName.startsWith('v') || tagName.startsWith('V')) {
        tagName = tagName.substring(1);
      }

      if (tagName.isEmpty) return null;

      final String releaseNotes = json['body'] as String? ?? 'Tidak ada catatan rilis.';
      final String htmlUrl = json['html_url'] as String? ?? '';

      // Find the first APK asset
      String downloadUrl = '';
      final List<dynamic> assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final String assetName = asset['name'] as String? ?? '';
        if (assetName.toLowerCase().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }

      // Fallback to html_url if no APK asset found
      if (downloadUrl.isEmpty) {
        downloadUrl = htmlUrl;
      }

      // Compare versions — only notify if remote is strictly newer
      if (_compareVersions(tagName, installedVersion) > 0) {
        return UpdateInfo(
          latestVersion: tagName,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
          htmlUrl: htmlUrl,
        );
      }

      return null;
    } catch (e) {
      // Gracefully handle any errors (network issues, JSON parsing, etc.)
      return null;
    }
  }

  /// Opens the download URL in the system browser so the user can download
  /// and install the APK.
  static Future<bool> launchDownloadUrl(String downloadUrl) async {
    try {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Compares two semantic version strings (e.g. "1.2.3" vs "1.3.0").
  /// Returns a positive number if [a] is newer than [b], negative if older,
  /// and 0 if they are equal.
  static int _compareVersions(String a, String b) {
    final List<int> partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final List<int> partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final int length = partsA.length > partsB.length ? partsA.length : partsB.length;

    for (int i = 0; i < length; i++) {
      final int segA = i < partsA.length ? partsA[i] : 0;
      final int segB = i < partsB.length ? partsB[i] : 0;

      if (segA != segB) {
        return segA - segB;
      }
    }

    return 0;
  }
}
