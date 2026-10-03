import 'dart:convert';

import 'package:anban/services/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const release = {
  'versionCode': 2,
  'versionName': '1.0.1',
  'downloadUrl': 'https://downloads.example.com/anban.apk',
  'releaseNotes': '修复问题',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rejects invalid versions and unsafe download links', () {
    expect(AndroidRelease.fromJson(release).versionCode, 2);
    for (final invalid in [
      null,
      [],
      {...release, 'versionCode': '2'},
      {...release, 'versionCode': 0},
      {...release, 'versionCode': 2100000001},
      {...release, 'versionName': ' '},
      {...release, 'releaseNotes': 42},
      for (final link in [
        'http://a.test/a.apk',
        'intent://install',
        'https:///a.apk',
        'https://user:pass@a.test/a.apk',
      ])
        {...release, 'downloadUrl': link},
    ]) {
      expect(() => AndroidRelease.fromJson(invalid), throwsFormatException);
    }
  });

  test('public update API distinguishes disabled and failed checks', () async {
    for (final status in [200, 204, 404, 503]) {
      final future = http.runWithClient(
        AndroidRelease.fetch,
        () => MockClient((request) async {
          expect(request.url.path, '/api/v1/app/android-update');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response.bytes(
            status == 200 ? utf8.encode(jsonEncode(release)) : [],
            status,
          );
        }),
      );
      if (status == 200) {
        expect((await future)?.releaseNotes, '修复问题');
      } else if (status == 204) {
        expect(await future, isNull);
      } else {
        await expectLater(future, throwsStateError);
      }
    }
  });

  testWidgets(
    'prompts only for newer APKs and opens download after confirmation',
    (tester) async {
      const versionChannel = MethodChannel('app.anban.anban/version');
      const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var installedCode = 2;
      var status = 200;
      var automatic = false;
      var launchSucceeds = true;
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        versionChannel,
        (_) async => {'versionCode': installedCode, 'versionName': '1.0.1'},
      );
      messenger.setMockMethodCallHandler(urlChannel, (call) async {
        launches.add(call);
        return launchSucceeds;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(versionChannel, null);
        messenger.setMockMethodCallHandler(urlChannel, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => http.runWithClient(
                  () => AppUpdate.check(context, automatic: automatic),
                  () => MockClient(
                    (_) async => http.Response.bytes(
                      utf8.encode(jsonEncode(release)),
                      status,
                    ),
                  ),
                ),
                child: const Text('检查更新'),
              ),
            ),
          ),
        ),
      );
      Future<void> check() async {
        messengerKey.currentState!.clearSnackBars();
        messengerKey.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
      }

      for (final code in [2, 3]) {
        installedCode = code;
        await check();
        expect(find.byType(AlertDialog), findsNothing);
      }
      installedCode = 1;
      await check();
      expect(find.text('发现新版本 1.0.1'), findsOneWidget);
      expect(launches, isEmpty);
      await tester.tap(find.text('稍后再说'));
      await tester.pumpAndSettle();
      expect(launches, isEmpty);
      await check();
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(launches.single.arguments['url'], release['downloadUrl']);
      expect(launches.single.arguments['useWebView'], isFalse);

      // Automatic checks are quiet on failure, but an explicit download failure is visible.
      automatic = true;
      status = 503;
      await check();
      expect(find.text('检查更新失败，请检查网络后重试'), findsNothing);
      automatic = false;
      await check();
      expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
      automatic = true;
      status = 200;
      launchSucceeds = false;
      await check();
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(find.text('无法打开下载链接，请稍后重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
