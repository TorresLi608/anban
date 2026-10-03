import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';
import 'account.dart';
import 'sync.dart';

class AndroidRelease {
  final int versionCode;
  final String versionName, releaseNotes;
  final Uri downloadUrl;

  AndroidRelease._(
    this.versionCode,
    this.versionName,
    this.downloadUrl,
    this.releaseNotes,
  );

  factory AndroidRelease.fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('更新信息格式错误');
    }
    final code = value['versionCode'];
    final name = value['versionName'];
    final link = value['downloadUrl'];
    final notes = value['releaseNotes'] ?? '';
    final uri = link is String ? Uri.tryParse(link) : null;
    if (code is! int ||
        code < 1 ||
        code > 2100000000 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 64 ||
        notes is! String ||
        notes.length > 4000 ||
        uri == null ||
        !uri.isScheme('https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('更新信息无效，请稍后重试');
    }
    return AndroidRelease._(code, name, uri, notes);
  }

  static Future<AndroidRelease?> fetch() async {
    final uri = VaultSync(
      Account.apiBase,
      '',
    ).url.replace(path: '/api/v1/app/android-update');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) throw StateError('更新服务暂不可用');
    return AndroidRelease.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
}

class AppUpdate {
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool _checking = false;

  static Future<void> check(
    BuildContext context, {
    bool automatic = false,
  }) async {
    if (!supported) return;
    if (_checking) {
      if (!automatic) toast(context, '正在检查更新，请稍候');
      return;
    }
    _checking = true;
    var openingDownload = false;
    try {
      final installed = await const MethodChannel('app.anban.anban/version')
          .invokeMapMethod<String, dynamic>('getVersion');
      final code = installed?['versionCode'];
      if (code is! int || code < 1) throw StateError('无法读取当前版本');
      final release = await AndroidRelease.fetch();
      if (!context.mounted) return;
      if (release == null || release.versionCode <= code) {
        if (!automatic) {
          toast(
            context,
            release == null
                ? '暂未发布更新'
                : '当前已是最新版本（${installed?['versionName']}）',
          );
        }
        return;
      }
      // Avoid interrupting a login/form dialog opened while the request was pending.
      if (automatic && ModalRoute.of(context)?.isCurrent != true) return;
      final download = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('发现新版本 ${release.versionName}'),
          content: SingleChildScrollView(
            child: Text(
              [
                if (release.releaseNotes.isNotEmpty) release.releaseNotes,
                '将打开浏览器下载新版，下载完成后请按系统提示安装。',
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('前往下载'),
            ),
          ],
        ),
      );
      if (download != true || !context.mounted) return;
      openingDownload = true;
      // ponytail: browser handles downloading and installation; no in-app APK manager.
      if (!await launchUrl(
        release.downloadUrl,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('无法打开下载链接');
      }
    } catch (_) {
      if (context.mounted && (!automatic || openingDownload)) {
        toast(context, openingDownload ? '无法打开下载链接，请稍后重试' : '检查更新失败，请检查网络后重试');
      }
    } finally {
      _checking = false;
    }
  }
}

/// Kept above the login/home switch so automatic checks run once per app launch.
class AppUpdatePrompt extends StatefulWidget {
  final Widget child;
  const AppUpdatePrompt({super.key, required this.child});

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdate.check(context, automatic: true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
