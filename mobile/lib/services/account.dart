import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/store.dart';
import '../data/vault.dart';
import 'sync.dart';

class Account {
  static const apiBase = String.fromEnvironment(
    'ANBAN_API_URL',
    defaultValue: 'http://localhost:8080',
  );
  static Map<String, dynamic>? current;
  static VaultSync? _api;
  static String? _password;

  static Future<void> login(
    CareStore store,
    String base,
    String username,
    String password,
    bool register,
    String encryptionPassword,
  ) async {
    if (encryptionPassword.runes.length < 6) {
      throw const FormatException('资料加密密码至少 6 个字符');
    }
    final guest = VaultSync(base, '');
    final response = guest.check(
      await http
          .post(
            guest.url.replace(
              path: '/api/v1/auth/${register ? 'register' : 'login'}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30)),
    );
    if (!RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(response['userId']?.toString() ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(response['token']?.toString() ?? '')) {
      throw const FormatException('服务器返回了无效会话');
    }
    final api = VaultSync(base, response['token']);
    await store.exclusive(() async {
      final vault = await LocalVault.memory();
      try {
        final options = api.check(
          await http
              .get(
                api.url.replace(path: '/api/v1/config/health-options'),
                headers: api.headers,
              )
              .timeout(const Duration(seconds: 30)),
        );
        final configured = options.map(
          (key, value) => MapEntry(key, List<String>.from(value as List)),
        );
        if ([
          'stoolStatus',
          'urineStatus',
          'urineColor',
          'urineAppearance',
        ].any((key) => configured[key]?.isNotEmpty != true)) {
          throw const FormatException('健康选项配置不完整');
        }
        final remote = await api.pull(encryptionPassword, allowEmpty: true);
        final data = await vault.restore({
          'data': remote.data.toJson(),
          'files': remote.files,
        });
        // Remove the persisted session from older versions; new sessions live only in memory.
        await const FlutterSecureStorage().delete(key: 'anban-account');
        current = {
          ...response,
          'server': guest.url.replace(path: '').toString(),
        };
        _api = api;
        _password = encryptionPassword;
        store.healthOptions = configured;
        store.publish = (data, vault) =>
            api.save(data, vault, encryptionPassword);
        await store.replaceVault(vault, data);
      } catch (_) {
        await vault.close();
        rethrow;
      }
    });
  }

  static Future<void> refresh(CareStore store) => store.exclusive(() async {
    if (_api == null || _password == null) throw StateError('请先登录');
    final remote = await _api!.pull(_password!, allowEmpty: true);
    final vault = await LocalVault.memory();
    try {
      final data = await vault.restore({
        'data': remote.data.toJson(),
        'files': remote.files,
      });
      await store.replaceVault(vault, data);
    } catch (_) {
      await vault.close();
      rethrow;
    }
  });

  static Future<void> logout(CareStore store) => store.exclusive(() async {
    final api = _api;
    if (api != null) {
      final response = await http
          .post(
            api.url.replace(path: '/api/v1/auth/logout'),
            headers: api.headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 401) api.check(response);
    }
    final vault = await LocalVault.memory();
    current = null;
    _api = null;
    _password = null;
    store.publish = (_, _) async => throw StateError('请先登录');
    await store.replaceVault(vault, CareData());
  });

  static String get scope {
    final session = current;
    if (session == null) return '';
    final uri = VaultSync(session['server'], session['token']).url;
    return '${uri.host}_${uri.port}_${session['userId']}';
  }
}
