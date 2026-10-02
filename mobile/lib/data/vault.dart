import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sembast/sembast_memory.dart';

import 'models.dart';
import 'database.dart';

final _cipher = AesGcm.with256bits();
List<int> randomBytes(int length) {
  final r = Random.secure();
  return List.generate(length, (_) => r.nextInt(256));
}

Future<Map<String, dynamic>> encryptBytes(
  List<int> bytes,
  SecretKey key,
) async {
  final box = await _cipher.encrypt(bytes, secretKey: key);
  return {
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
}

Future<Uint8List> decryptBytes(Map<String, dynamic> e, SecretKey key) async =>
    Uint8List.fromList(
      await _cipher.decrypt(
        SecretBox(
          base64Decode(e['ciphertext']),
          nonce: base64Decode(e['nonce']),
          mac: Mac(base64Decode(e['mac'])),
        ),
        secretKey: key,
      ),
    );

Future<SecretKey> passwordKey(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 210000,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
Future<Map<String, dynamic>> sealBackup(
  Map<String, dynamic> data,
  String password,
) async {
  if (password.runes.length < 6) {
    throw const FormatException('备份密码至少 6 个字符');
  }
  final salt = randomBytes(16);
  final e = await encryptBytes(
    utf8.encode(jsonEncode(data)),
    await passwordKey(password, salt),
  );
  return {
    'version': 1,
    'algorithm': 'AES-256-GCM',
    'iterations': 210000,
    'salt': base64Encode(salt),
    ...e,
  };
}

Future<Map<String, dynamic>> openBackup(
  Map<String, dynamic> e,
  String password,
) async {
  if (e['version'] != 1 ||
      e['algorithm'] != 'AES-256-GCM' ||
      e['iterations'] != 210000 ||
      base64Decode(e['salt']).length != 16) {
    throw const FormatException('不支持的加密备份格式');
  }
  final bytes = await decryptBytes(
    e,
    await passwordKey(password, base64Decode(e['salt'])),
  );
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
}

class LocalVault {
  final Database db;
  final SecretKey key;
  final _store = stringMapStoreFactory.store('vault');
  final bool ephemeral;
  LocalVault(this.db, this.key, {this.ephemeral = false});
  Future<void> close() async {
    final path = db.path;
    await db.close();
    if (ephemeral) await databaseFactoryMemory.deleteDatabase(path);
  }

  static Future<LocalVault> memory() async => LocalVault(
    await databaseFactoryMemory.openDatabase(newId()),
    SecretKey(randomBytes(32)),
    ephemeral: true,
  );

  // Only used to migrate data written by older app versions.
  static Future<LocalVault> open({String scope = ''}) async {
    const secure = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    );
    final key = await secure.read(key: 'anban-vault-key$scope');
    if (key == null) {
      throw StateError('没有可读取的旧版资料密钥。没有旧资料时无需迁移；如密钥丢失，请从加密备份恢复。');
    }
    final db = await openDatabase(scope);
    return LocalVault(db, SecretKey(base64Decode(key)));
  }

  Future<CareData> load() async {
    final e = await _store.record('state').get(db);
    if (e == null) {
      return CareData();
    }
    return CareData.fromJson(
      jsonDecode(utf8.decode(await decryptBytes(e, key))),
    );
  }

  Future<void> save(CareData data) async {
    await _store
        .record('state')
        .put(
          db,
          await encryptBytes(utf8.encode(jsonEncode(data.toJson())), key),
        );
  }

  Future<String> addAttachment(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('附件大小应为 1 字节至 20 MB');
    }
    final id = newId();
    await _store.record('file:$id').put(db, await encryptBytes(bytes, key));
    return id;
  }

  Future<Uint8List> attachment(String id) async {
    final e = await _store.record('file:$id').get(db);
    if (e == null) {
      throw StateError('本机附件不存在');
    }
    return decryptBytes(e, key);
  }

  Future<Map<String, dynamic>> backup(CareData data) async {
    final files = <String, String>{};
    for (final id in data.records.expand(attachmentIds).toSet()) {
      if (id.isNotEmpty) {
        files[id] = base64Encode(await attachment(id));
      }
    }
    return {'data': data.toJson(), 'files': files};
  }

  Future<CareData> restore(Map<String, dynamic> backup) async {
    final data = CareData.fromJson(backup['data']);
    final files = Map<String, String>.from(backup['files'] as Map);
    final encrypted = <String, Map<String, dynamic>>{};
    for (final id in data.records.expand(attachmentIds).toSet()) {
      if (id.isEmpty) {
        continue;
      }
      if (!files.containsKey(id)) {
        throw const FormatException('备份缺少附件，未恢复任何数据');
      }
      final bytes = base64Decode(files[id]!);
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('附件过大');
      }
      encrypted[id] = await encryptBytes(bytes, key);
    }
    final state = await encryptBytes(
      utf8.encode(jsonEncode(data.toJson())),
      key,
    );
    await db.transaction((txn) async {
      await _store.delete(txn);
      await _store.record('state').put(txn, state);
      for (final e in encrypted.entries) {
        await _store.record('file:${e.key}').put(txn, e.value);
      }
    });
    return data;
  }

  Future<void> clear() async {
    await _store.delete(db);
  }
}
