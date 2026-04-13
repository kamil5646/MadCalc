import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/services/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    test('normalizes and compares semantic versions', () {
      expect(AppUpdateService.normalizeVersion('v0.3.7'), '0.3.7');
      expect(
        AppUpdateService.compareVersions('0.3.8', '0.3.7'),
        greaterThan(0),
      );
      expect(AppUpdateService.compareVersions('0.3.7', '0.3.7+10'), 0);
      expect(AppUpdateService.compareVersions('1.0.0', '1.0'), 0);
      expect(AppUpdateService.compareVersions('1.0.1', '1.0.9'), lessThan(0));
    });

    test(
      'returns a platform specific update when a newer release exists',
      () async {
        final service = AppUpdateService(
          platform: AppUpdatePlatform.windows,
          buildInfoLoader: () async =>
              const AppBuildInfo(version: '0.3.7', buildNumber: '10'),
          latestReleaseLoader: (uri, headers) async {
            expect(
              uri.toString(),
              'https://api.github.com/repos/kamil5646/MadCalc/releases/latest',
            );
            expect(headers['Accept'], 'application/vnd.github+json');
            expect(headers['X-GitHub-Api-Version'], '2022-11-28');

            return <String, dynamic>{
              'tag_name': 'v0.3.8',
              'name': 'MadCalc v0.3.8',
              'html_url':
                  'https://github.com/kamil5646/MadCalc/releases/tag/v0.3.8',
              'body': '- szybsze liczenie\n- poprawki PDF',
              'published_at': '2026-04-13T10:00:00Z',
              'assets': [
                {
                  'name': 'MadCalc-macos-v0.3.8.zip',
                  'browser_download_url': 'https://example.com/macos.zip',
                },
                {
                  'name': 'MadCalc-windows-v0.3.8.zip',
                  'browser_download_url': 'https://example.com/windows.zip',
                },
              ],
            };
          },
        );

        final result = await service.checkForUpdate();

        expect(result.currentVersion, '0.3.7');
        expect(result.availableUpdate, isNotNull);
        expect(result.availableUpdate!.latestVersion, '0.3.8');
        expect(result.availableUpdate!.platformLabel, 'Windows');
        expect(result.availableUpdate!.hasDirectDownload, isTrue);
        expect(
          result.availableUpdate!.downloadUrl,
          'https://example.com/windows.zip',
        );
      },
    );

    test('returns no update when the installed version is current', () async {
      final service = AppUpdateService(
        platform: AppUpdatePlatform.android,
        buildInfoLoader: () async =>
            const AppBuildInfo(version: '0.3.7', buildNumber: '10'),
        latestReleaseLoader: (uri, headers) async {
          expect(uri.path, '/repos/kamil5646/MadCalc/releases/latest');
          expect(headers['User-Agent'], 'MadCalc-Updater');
          return <String, dynamic>{
            'tag_name': 'v0.3.7',
            'html_url':
                'https://github.com/kamil5646/MadCalc/releases/tag/v0.3.7',
            'assets': const [],
          };
        },
      );

      final result = await service.checkForUpdate();

      expect(result.currentVersion, '0.3.7');
      expect(result.availableUpdate, isNull);
    });

    test(
      'falls back to the release page when there is no asset for the platform',
      () async {
        final service = AppUpdateService(
          platform: AppUpdatePlatform.windows,
          buildInfoLoader: () async =>
              const AppBuildInfo(version: '0.3.7', buildNumber: '10'),
          latestReleaseLoader: (uri, headers) async {
            expect(uri.host, 'api.github.com');
            expect(headers['Accept'], 'application/vnd.github+json');
            return <String, dynamic>{
              'tag_name': 'v0.3.9',
              'name': 'MadCalc v0.3.9',
              'html_url':
                  'https://github.com/kamil5646/MadCalc/releases/tag/v0.3.9',
              'body': 'Nowa wersja bez paczki Windows jeszcze przez chwile.',
              'assets': [
                {
                  'name': 'MadCalc-macos-v0.3.9.zip',
                  'browser_download_url': 'https://example.com/macos.zip',
                },
              ],
            };
          },
        );

        final result = await service.checkForUpdate();

        expect(result.availableUpdate, isNotNull);
        expect(result.availableUpdate!.hasDirectDownload, isFalse);
        expect(
          result.availableUpdate!.downloadUrl,
          'https://github.com/kamil5646/MadCalc/releases/tag/v0.3.9',
        );
      },
    );
  });
}
