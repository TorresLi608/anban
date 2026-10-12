import 'dart:convert';

import 'package:anban/data/models.dart';
import 'package:anban/data/planning.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/services/account.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = FlutterSecureStorage();
  const encryptionPassword = 'cloud-secret';
  final token = 'a' * 64;
  final userId = 'b' * 64;
  late CareStore store;
  late Map<String, dynamic> encrypted;
  late List<String> requests;
  var status = 200;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    Account.current = null;
    store = CareStore(await LocalVault.memory(), CareData());
    encrypted = await sealBackup({
      'data': CareData(profile: {'name': '云端患者'}).toJson(),
      'files': <String, dynamic>{},
    }, encryptionPassword);
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
      return http.Response(
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
        200,
      );
    }
    expect(request.headers['authorization'], 'Bearer $token');
    if (status != 200) {
      return http.Response.bytes(utf8.encode('{"error":"暂不可用"}'), status);
    }
    if (path == '/api/v1/config/health-options') {
      return http.Response.bytes(
        utf8.encode(jsonEncode(defaultHealthOptions)),
        200,
      );
    }
    if (path == '/api/v1/auth/logout') return http.Response('{"ok":true}', 200);
    if (path == '/api/v1/vault') {
      if (request.method == 'PUT') {
        encrypted = Map<String, dynamic>.from(jsonDecode(request.body));
        return http.Response('{"revision":2}', 200);
      }
      return http.Response(jsonEncode({'data': encrypted, 'revision': 1}), 200);
    }
    throw StateError('Unexpected request: $path');
  });

  Future<void> login({
    String secret = encryptionPassword,
    String username = 'patient',
  }) => Account.login(
    store,
    Account.apiBase,
    username,
    'login-secret',
    false,
    secret,
  );

  void check(String name, Future<void> Function() body) {
    test(name, () => http.runWithClient(body, server));
  }

  check(
    'restart restores session, decrypts cloud data and saves without login',
    () async {
      await login();
      expect(store.data.profile['name'], '云端患者');
      final saved = await secure.readAll();
      expect(saved.values.any((v) => v.contains('login-secret')), isFalse);
      expect(saved.values.any((v) => v.contains('云端患者')), isFalse);
      await store.vault.close();
      store.dispose();
      store = CareStore(await LocalVault.memory(), CareData());
      Account.current = null;
      requests.clear();

      expect(await Account.restore(store), isTrue);
      expect(Account.current?['username'], 'patient');
      expect(store.data.profile['name'], '云端患者');
      expect(requests, isNot(contains('/api/v1/auth/login')));
      await store.profile({'name': '已修改'});
      expect(
        (await openBackup(
          encrypted,
          encryptionPassword,
        ))['data']['profile']['name'],
        '已修改',
      );
    },
  );

  check(
    'logout clears session but remembers encryption password for this account',
    () async {
      await login();
      await Account.logout(store);
      expect(Account.current, isNull);
      expect(await secure.read(key: 'anban-account'), isNull);
      expect(await Account.restore(store), isFalse);
      expect(store.data.profile, isEmpty);
      await login(secret: '', username: 'PATIENT');
      expect(store.data.profile['name'], '云端患者');
      await expectLater(
        login(secret: '', username: 'other_patient'),
        throwsFormatException,
      );
      await expectLater(
        Account.login(
          store,
          'https://other.example.com',
          'patient',
          'login-secret',
          false,
          '',
        ),
        throwsFormatException,
      );
    },
  );

  check(
    'incorrect encryption password never replaces valid saved credentials',
    () async {
      await login();
      final saved = await secure.readAll();
      await expectLater(
        login(secret: 'wrong-secret'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      expect(await secure.readAll(), saved);
      expect(store.data.profile['name'], '云端患者');
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

  check('revoked and expired sessions return to login while retaining encryption password', () async {
    await login();
    Account.current = null;
    status = 401;
    expect(await Account.restore(store), isFalse);
    expect(await secure.read(key: 'anban-account'), isNull);
    status = 200;
    await login(secret: '');
    final session = jsonDecode((await secure.read(key: 'anban-account'))!);
    session['expiresAt'] = DateTime.now()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    await secure.write(key: 'anban-account', value: jsonEncode(session));
    Account.current = null;
    requests.clear();
    expect(await Account.restore(store), isFalse);
    expect(requests, isEmpty);
    await login(secret: '');
    expect(store.data.profile['name'], '云端患者');
  });
}
