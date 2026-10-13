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
    defaultValue: 'http://localhost:8024',
  );
  static Map<String, dynamic>? current;
  static VaultSync? _api;
  static String? _password;
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  static const _sessionKey = 'anban-account';

  static String _passwordKey(String base, String username) {
    final identity = [
      VaultSync(base, '').url.replace(path: '').toString(),
      username.trim().toLowerCase(),
    ];
    return 'anban-encryption:${base64UrlEncode(utf8.encode(jsonEncode(identity)))}';
  }

  static Future<bool> restore(CareStore store) async {
    final saved = await _secure.read(key: _sessionKey);
    if (saved == null) return false;
    late Map<String, dynamic> session;
    try {
      session = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      final expires = DateTime.tryParse(session['expiresAt'] as String? ?? '');
      if (session['server'] is! String ||
          session['username'] is! String ||
          !_validSession(session) ||
          expires == null ||
          !expires.isAfter(DateTime.now()) ||
          VaultSync(session['server'], '').url != VaultSync(apiBase, '').url) {
        await _secure.delete(key: _sessionKey);
        return false;
      }
    } on FormatException {
      await _secure.delete(key: _sessionKey);
      return false;
    } on TypeError {
      await _secure.delete(key: _sessionKey);
      return false;
    }
    final encryptionPassword = await _secure.read(
      key: _passwordKey(session['server'], session['username']),
    );
    if (encryptionPassword == null || encryptionPassword.runes.length < 6) {
      await _secure.delete(key: _sessionKey);
      return false;
    }
    try {
      await _connect(store, session, encryptionPassword);
      return true;
    } on VaultSyncException catch (e) {
      if (e.statusCode != 401) rethrow;
      await _secure.delete(key: _sessionKey);
      return false;
    }
  }

  static bool _validSession(Map<String, dynamic> session) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(session['userId']?.toString() ?? '') &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(session['token']?.toString() ?? '');

  static Future<void> login(
    CareStore store,
    String base,
    String username,
    String password,
    bool register,
    String encryptionPassword,
  ) async {
    if (encryptionPassword.isEmpty && !register) {
      encryptionPassword =
          await _secure.read(key: _passwordKey(base, username)) ?? '';
    }
    if (encryptionPassword.runes.length < 6) {
      throw const FormatException('请填写资料加密密码（至少 6 个字符），成功登录后此设备会记住');
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
    if (!_validSession(response)) {
      throw const FormatException('服务器返回了无效会话');
    }
    await _connect(store, {
      ...response,
      'server': guest.url.replace(path: '').toString(),
    }, encryptionPassword);
  }

  static Future<void> _connect(
    CareStore store,
    Map<String, dynamic> session,
    String encryptionPassword,
  ) async {
    final api = VaultSync(session['server'], session['token']);
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
        await api.loadInto(vault, remote, encryptionPassword);
        final data = remote.data;
        // Persist only after cloud data has been successfully decrypted.
        await _secure.write(
          key: _passwordKey(session['server'], session['username']),
          value: encryptionPassword,
        );
        await _secure.write(key: _sessionKey, value: jsonEncode(session));
        current = session;
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
      await _api!.loadInto(vault, remote, _password!);
      await store.replaceVault(vault, remote.data);
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
    await _secure.delete(key: _sessionKey);
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

  static Future<Map<String, dynamic>> reminderRequest(
    String method, {
    Map<String, dynamic>? body,
    bool test = false,
  }) async {
    final api = _api;
    if (api == null) throw StateError('请先登录');
    final request = http.Request(
      method,
      api.url.replace(
        path: test ? '/api/v1/reminders/test' : '/api/v1/reminders',
      ),
    );
    request.headers.addAll(api.headers);
    if (body != null) {
      request.body = jsonEncode({...body, 'revision': api.revision});
    }
    return api.check(
      await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      ).timeout(const Duration(seconds: 30)),
    );
  }
}
