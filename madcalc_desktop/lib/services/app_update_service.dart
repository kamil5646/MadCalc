import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_info.dart';

typedef AppBuildInfoLoader = Future<AppBuildInfo> Function();
typedef LatestReleaseLoader =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, String> headers);

class AppUpdateService {
  AppUpdateService({
    AppBuildInfoLoader? buildInfoLoader,
    LatestReleaseLoader? latestReleaseLoader,
    AppUpdatePlatform? platform,
    this.owner = 'kamil5646',
    this.repo = 'MadCalc',
  }) : _buildInfoLoader = buildInfoLoader ?? _defaultBuildInfoLoader,
       _latestReleaseLoader =
           latestReleaseLoader ?? _defaultLatestReleaseLoader,
       _platform = platform ?? AppUpdatePlatform.current();

  final AppBuildInfoLoader _buildInfoLoader;
  final LatestReleaseLoader _latestReleaseLoader;
  final AppUpdatePlatform _platform;
  final String owner;
  final String repo;

  Future<String> loadCurrentVersion() async {
    final buildInfo = await _buildInfoLoader();
    final normalized = normalizeVersion(buildInfo.version);
    if (normalized.isEmpty) {
      throw const AppUpdateException(
        'Nie udało się odczytać aktualnej wersji aplikacji.',
      );
    }
    return normalized;
  }

  Future<AppUpdateCheck> checkForUpdate({String? currentVersion}) async {
    final installedVersion =
        currentVersion == null || currentVersion.trim().isEmpty
        ? await loadCurrentVersion()
        : normalizeVersion(currentVersion);

    final release = await _fetchLatestRelease();
    final releaseTag = (release['tag_name'] as String?) ?? '';
    final latestVersion = normalizeVersion(releaseTag);

    if (latestVersion.isEmpty) {
      throw const AppUpdateException(
        'GitHub zwrócił release bez poprawnego numeru wersji.',
      );
    }

    if (compareVersions(latestVersion, installedVersion) <= 0) {
      return AppUpdateCheck(
        currentVersion: installedVersion,
        availableUpdate: null,
      );
    }

    final assets = ((release['assets'] as List?) ?? const <Object>[])
        .whereType<Map>()
        .map((asset) => Map<String, dynamic>.from(asset))
        .toList(growable: false);
    final asset = _selectAssetForPlatform(assets);
    final releasePageUrl =
        (release['html_url'] as String?) ?? _fallbackReleasePageUrl(releaseTag);
    final publishedAtValue = release['published_at'] as String?;

    return AppUpdateCheck(
      currentVersion: installedVersion,
      availableUpdate: AppUpdateInfo(
        currentVersion: installedVersion,
        latestVersion: latestVersion,
        releaseName: (release['name'] as String?)?.trim().isNotEmpty == true
            ? (release['name'] as String).trim()
            : 'MadCalc v$latestVersion',
        releaseNotes: ((release['body'] as String?) ?? '').trim(),
        releasePageUrl: releasePageUrl,
        downloadUrl:
            (asset?['browser_download_url'] as String?) ?? releasePageUrl,
        platformLabel: _platform.label,
        hasDirectDownload: asset != null,
        assetName: asset?['name'] as String?,
        publishedAt: publishedAtValue == null
            ? null
            : DateTime.tryParse(publishedAtValue),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    return _latestReleaseLoader(uri, const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'MadCalc-Updater',
    });
  }

  String _fallbackReleasePageUrl(String tag) {
    final safeTag = tag.trim().isEmpty ? 'latest' : 'tag/$tag';
    return 'https://github.com/$owner/$repo/releases/$safeTag';
  }

  Map<String, dynamic>? _selectAssetForPlatform(
    List<Map<String, dynamic>> assets,
  ) {
    for (final asset in assets) {
      final rawName = asset['name'] as String?;
      if (rawName == null) {
        continue;
      }

      final name = rawName.toLowerCase();
      if (_platform.matchesAssetName(name)) {
        return asset;
      }
    }
    return null;
  }

  static String normalizeVersion(String rawVersion) {
    final trimmed = rawVersion.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }

  static int compareVersions(String leftVersion, String rightVersion) {
    final leftParts = _versionParts(leftVersion);
    final rightParts = _versionParts(rightVersion);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final left = index < leftParts.length ? leftParts[index] : 0;
      final right = index < rightParts.length ? rightParts[index] : 0;

      if (left != right) {
        return left.compareTo(right);
      }
    }

    return 0;
  }

  static List<int> _versionParts(String rawVersion) {
    final coreVersion = normalizeVersion(
      rawVersion,
    ).split(RegExp(r'[-+]')).first;
    return coreVersion
        .split('.')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  static Future<AppBuildInfo> _defaultBuildInfoLoader() async {
    final info = await PackageInfo.fromPlatform();
    return AppBuildInfo(version: info.version, buildNumber: info.buildNumber);
  }

  static Future<Map<String, dynamic>> _defaultLatestReleaseLoader(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      headers.forEach(request.headers.set);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final payload = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.notFound) {
        throw const AppUpdateException('Nie znaleziono release dla MadCalc.');
      }

      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException(
          'GitHub odpowiedział kodem ${response.statusCode} podczas sprawdzania aktualizacji.',
        );
      }

      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        throw const AppUpdateException(
          'GitHub zwrócił niepoprawną odpowiedź aktualizacji.',
        );
      }

      return Map<String, dynamic>.from(decoded);
    } on SocketException {
      throw const AppUpdateException(
        'Nie udało się sprawdzić aktualizacji. Sprawdź połączenie z internetem.',
      );
    } on TimeoutException {
      throw const AppUpdateException(
        'Sprawdzanie aktualizacji trwało zbyt długo. Spróbuj ponownie za chwilę.',
      );
    } on FormatException {
      throw const AppUpdateException(
        'GitHub zwrócił odpowiedź, której nie udało się odczytać.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;
}

enum AppUpdatePlatform {
  android,
  macOS,
  windows,
  unsupported;

  static AppUpdatePlatform current() {
    if (Platform.isAndroid) {
      return AppUpdatePlatform.android;
    }
    if (Platform.isMacOS) {
      return AppUpdatePlatform.macOS;
    }
    if (Platform.isWindows) {
      return AppUpdatePlatform.windows;
    }
    return AppUpdatePlatform.unsupported;
  }

  String get label {
    return switch (this) {
      AppUpdatePlatform.android => 'Android',
      AppUpdatePlatform.macOS => 'macOS',
      AppUpdatePlatform.windows => 'Windows',
      AppUpdatePlatform.unsupported => 'tej platformy',
    };
  }

  bool matchesAssetName(String assetName) {
    return switch (this) {
      AppUpdatePlatform.android =>
        assetName.contains('android') && assetName.endsWith('.apk'),
      AppUpdatePlatform.macOS =>
        assetName.contains('macos') &&
            (assetName.endsWith('.zip') || assetName.endsWith('.dmg')),
      AppUpdatePlatform.windows =>
        assetName.contains('windows') &&
            (assetName.endsWith('.zip') ||
                assetName.endsWith('.exe') ||
                assetName.endsWith('.msix')),
      AppUpdatePlatform.unsupported => false,
    };
  }
}
