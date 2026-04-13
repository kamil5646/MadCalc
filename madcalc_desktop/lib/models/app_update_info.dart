class AppUpdateCheck {
  const AppUpdateCheck({
    required this.currentVersion,
    required this.availableUpdate,
  });

  final String currentVersion;
  final AppUpdateInfo? availableUpdate;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.downloadUrl,
    required this.platformLabel,
    required this.hasDirectDownload,
    this.assetName,
    this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String releasePageUrl;
  final String downloadUrl;
  final String platformLabel;
  final bool hasDirectDownload;
  final String? assetName;
  final DateTime? publishedAt;

  String get primaryActionLabel =>
      hasDirectDownload ? 'Pobierz aktualizację' : 'Otwórz release';
}
