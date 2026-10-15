import 'dart:convert';

import 'package:anban/data/models.dart';
import 'package:anban/data/planning.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/services/account.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = FlutterSecureStorage();
  final token = 'a' * 64;
  final userId = 'b' * 64;
  late CareStore store;
  late Map<String, dynamic> cloudPayload;
  late List<String> requests;
  var status = 200;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    Account.current = null;
    store = CareStore(await LocalVault.memory(), CareData());
    cloudPayload = {
      'data': CareData(profile: {'name': '云端用户'}).toJson(),
      'files': <String, dynamic>{},
    };
    requests = [];
    status = 200;
  });
  tearDown(() async {
    Account.current = null;
    await store.vault.close();
    store.dispose();
  });

  MockClient server() => MockClient((request) async {
    final path = request.url.path;
    requests.add(path);
    if (path == '/api/v1/auth/login') {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'token': token,
            'userId': userId,
            'username': jsonDecode(
              request.body,
            )['username'].toString().toLowerCase(),
            'expiresAt': DateTime.now()
                .add(const Duration(days: 30))
                .toIso8601String(),
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    expect(request.headers['authorization'], 'Bearer $token');
    if (status != 200) {
      return http.Response.bytes(
        utf8.encode('{"error":"暂不可用"}'),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path == '/api/v1/config/health-options') {
      return http.Response.bytes(
        utf8.encode(jsonEncode(defaultHealthOptions)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path == '/api/v1/auth/logout') {
      return http.Response.bytes(
        utf8.encode('{"ok":true}'),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path == '/api/v1/vault') {
      if (request.method == 'PUT') {
        cloudPayload = Map<String, dynamic>.from(jsonDecode(request.body));
        return http.Response.bytes(
          utf8.encode('{"revision":2}'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode({'data': cloudPayload, 'revision': 1})),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    throw StateError('Unexpected request: $path');
  });

  Future<void> login({String username = 'member'}) => Account.login(
    store,
    Account.apiBase,
    username,
    'login-secret',
    false,
  );

  void check(String name, Future<void> Function() body) {
    test(name, () => http.runWithClient(body, server));
  }

  check(
    'restart restores session, loads cloud data and saves without login',
    () async {
      await login();
      expect(store.data.profile['name'], '云端用户');
      final saved = await secure.readAll();
      expect(saved.values.any((v) => v.contains('login-secret')), isFalse);
      await store.vault.close();
      store.dispose();
      store = CareStore(await LocalVault.memory(), CareData());
      Account.current = null;
      requests.clear();

      expect(await Account.restore(store), isTrue);
      expect(Account.current?['username'], 'member');
      expect(store.data.profile['name'], '云端用户');
      expect(requests, isNot(contains('/api/v1/auth/login')));
      await store.profile({'name': '已修改'});
      expect(cloudPayload['data']['profile']['name'], '已修改');
    },
  );

  check(
    'logout clears session and resets local data',
    () async {
      await login();
      await Account.logout(store);
      expect(Account.current, isNull);
      expect(await secure.read(key: 'anban-account'), isNull);
      expect(await Account.restore(store), isFalse);
      expect(store.data.profile, isEmpty);
      await login(username: 'MEMBER');
      expect(store.data.profile['name'], '云端用户');
    },
  );

  check('temporary server failure preserves saved session for retry', () async {
    await login();
    final saved = await secure.read(key: 'anban-account');
    Account.current = null;
    status = 503;
    await expectLater(Account.restore(store), throwsStateError);
    expect(await secure.read(key: 'anban-account'), saved);
    status = 200;
    expect(await Account.restore(store), isTrue);
  });

  check('revoked and expired sessions return to login', () async {
    await login();
    Account.current = null;
    status = 401;
    expect(await Account.restore(store), isFalse);
    expect(await secure.read(key: 'anban-account'), isNull);
    status = 200;
    await login();
    final session = jsonDecode((await secure.read(key: 'anban-account'))!);
    session['expiresAt'] = DateTime.now()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    await secure.write(key: 'anban-account', value: jsonEncode(session));
    Account.current = null;
    requests.clear();
    expect(await Account.restore(store), isFalse);
    expect(requests, isEmpty);
    await login();
    expect(store.data.profile['name'], '云端用户');
  });

  check(
    'legacy encrypted cloud backup automatically decrypts with login password and migrates to plain',
    () async {
      final salt = randomBytes(16);
      final key = await passwordKey('login-secret', salt);
      final encrypted = await encryptBytes(
        utf8.encode(
          jsonEncode({
            'data': CareData(profile: {'name': '加密历史用户'}).toJson(),
            'files': <String, dynamic>{},
          }),
        ),
        key,
      );
      cloudPayload = {
        'version': 1,
        'algorithm': 'AES-256-GCM',
        'iterations': 210000,
        'salt': base64Encode(salt),
        ...encrypted,
      };

      await login();
      expect(store.data.profile['name'], '加密历史用户');
      // 验证已自动调用 PUT /api/v1/vault 转换为明文备份
      expect(cloudPayload.containsKey('ciphertext'), isFalse);
      expect(cloudPayload['data']['profile']['name'], '加密历史用户');
    },
  );
}
