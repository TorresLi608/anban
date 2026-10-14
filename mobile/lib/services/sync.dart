import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/attachments.dart';
import '../data/vault.dart';

class VaultSyncException extends StateError {
  final int statusCode;
  VaultSyncException(this.statusCode, super.message);
}

class VaultSync {
  final Uri url;
  final String token;
  int revision = 0;
  LocalVault? _stagedSource;
  final _staged = <String, RemoteAttachment>{};
  VaultSync(String base, this.token) : url = _url(base);
  static Uri _url(String base) {
    final uri = Uri.parse(base.trim());
    if ((!uri.isScheme('https') &&
            !(uri.isScheme('http') &&
                [
                  'localhost',
                  '127.0.0.1',
                  '10.0.2.2',
                  '::1',
                  // ponytail: temporary test server; remove after enabling HTTPS.
                  '103.236.97.108',
                ].contains(uri.host))) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请使用 HTTPS 服务地址；HTTP 仅允许本机或指定测试服务器');
    }
    return uri.replace(path: '/api/v1/vault');
  }

  Map<String, String> get headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  Map<String, dynamic> check(http.Response r) {
    if (r.statusCode != 200) {
      String message = '服务返回 ${r.statusCode}';
      try {
        message = jsonDecode(utf8.decode(r.bodyBytes))['error'] as String;
      } catch (_) {}
      throw VaultSyncException(r.statusCode, message);
    }
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(r.bodyBytes)) as Map,
    );
  }

  Future<RemoteAttachment> _upload(
    Stream<List<int>> source,
    String id, [
    String? password,
    String? filename,
  ]) async {
    final parts = <String>[];
    var size = 0;
    await for (final bytes in attachmentChunks(source)) {
      size += bytes.length;
      if (size > maxAttachmentBytes) throw StateError('单个文件最多 200 MB');
      final payload = {
        'file': base64Encode(bytes),
        'size': bytes.length,
        if (filename != null && filename.isNotEmpty) 'filename': filename,
      };
      final response = check(
        await http
            .post(
              url.replace(path: '/api/v1/files'),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 120)),
      );
      final remote = response['id'];
      if (remote is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(remote)) {
        throw const FormatException('服务器返回了无效附件标识');
      }
      parts.add(remote);
    }
    if (size == 0) throw const FormatException('不能保存空附件');
    return RemoteAttachment(parts, size: size);
  }

  Stream<List<int>> readAttachment(
    String id,
    RemoteAttachment file, [
    String? password,
  ]) async* {
    var total = 0;
    for (var i = 0; i < file.parts.length; i++) {
      final response = check(
        await http
            .get(
              url.replace(path: '/api/v1/files/${file.parts[i]}'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 120)),
      );
      final Uint8List bytes;
      if (response.containsKey('file')) {
        bytes = base64Decode(response['file'] as String);
      } else if (response.containsKey('ciphertext')) {
        // 兼容旧加密分块与旧版单文件载荷
        if (file.legacy || response.containsKey('salt')) {
          final value = await openBackup(response, password ?? '');
          if (value.containsKey('file')) {
            bytes = base64Decode(value['file'] as String);
          } else {
            bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
          }
        } else {
          final key = (file.salt != null && password != null)
              ? await passwordKey(password, base64Decode(file.salt!))
              : null;
          if (key == null) throw const FormatException('附件为加密数据，缺少解密密码');
          bytes = await decryptBytes(response, key, aad: utf8.encode('$id:$i'));
          final expected = i == file.parts.length - 1
              ? file.size! - i * attachmentChunkBytes
              : attachmentChunkBytes;
          if (bytes.length != expected) throw const FormatException('附件分块长度不完整');
        }
      } else {
        throw const FormatException('未知附件格式');
      }
      total += bytes.length;
      if (total > maxAttachmentBytes) {
        throw const FormatException('附件超过 200 MB');
      }
      yield bytes;
    }
  }

  Future<Uint8List> _readBytes(
    String id,
    RemoteAttachment file, [
    String? password,
  ]) async {
    final result = BytesBuilder(copy: false);
    await for (final bytes in readAttachment(id, file, password)) {
      result.add(bytes);
    }
    return result.takeBytes();
  }

  Future<void> save(CareData data, LocalVault vault, [String? password]) async {
    if (!identical(_stagedSource, vault)) {
      _staged.clear();
      _stagedSource = vault;
    }
    final files = <String, RemoteAttachment>{};
    for (final id in data.records.expand(attachmentIds).toSet()) {
      if (id.isEmpty) continue;
      final existing = identical(vault.remoteOwner, this)
          ? vault.remoteAttachments[id]
          : null;
      final filename = await vault.attachmentName(id);
      files[id] =
          existing ??
          _staged[id] ??
          await _upload(vault.attachmentStream(id), id, password, filename);
      _staged[id] = files[id]!;
    }
    final manifest = {
      'data': {
        ...data.toJson(),
        'settings': {
          for (final e in data.settings.entries)
            if (!['token', 'server'].contains(e.key) &&
                !e.key.startsWith('revision:'))
              e.key: e.value,
        },
      },
      'files': files.map((id, file) => MapEntry(id, file.toJson())),
    };
    final bytes = utf8.encode(jsonEncode(manifest));
    Map<String, dynamic> payload = manifest;
    if (bytes.length > attachmentChunkBytes) {
      // Large catalogs are chunked too; no fixed record/file count limit.
      final id = 'manifest-${newId()}';
      final reference = await _upload(Stream.value(bytes), id, password);
      payload = {'manifestId': id, 'manifest': reference.toJson()};
    }
    final response = check(
      await http
          .put(
            url,
            headers: {...headers, 'If-Match': '"$revision"'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60)),
    );
    revision = response['revision'] as int;
    vault.remoteOwner = this;
    vault.readRemote = (id, file) => readAttachment(id, file, password);
    vault.remoteAttachments.addAll(files);
    // Free staged bytes only after the server has committed their references.
    for (final id in files.keys) {
      await vault.releaseLocalAttachment(id);
    }
    _staged.clear();
  }

  Future<({
    CareData data,
    int revision,
    Map<String, RemoteAttachment> files,
    bool wasEncrypted,
  })>
  pull([String? password, bool allowEmpty = false]) async {
    final response = check(
      await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30)),
    );
    if (response['data'] == null) {
      if (!allowEmpty) throw StateError('服务器还没有备份');
      return (
        data: CareData(),
        revision: response['revision'] as int,
        files: <String, RemoteAttachment>{},
        wasEncrypted: false,
      );
    }
    var decrypted = Map<String, dynamic>.from(response['data'] as Map);
    var wasEncrypted = false;
    // 兼容旧版加密资料
    if (decrypted.containsKey('ciphertext') ||
        decrypted['version'] == 1 ||
        decrypted['algorithm'] == 'AES-256-GCM') {
      wasEncrypted = true;
      decrypted = await openBackup(decrypted, password ?? '');
    }
    if (decrypted['manifest'] != null) {
      final id = decrypted['manifestId'];
      if (id is! String || id.length > 100) {
        throw const FormatException('资料目录无效');
      }
      final bytes = await _readBytes(
        id,
        RemoteAttachment.fromJson(decrypted['manifest']),
        password,
      );
      decrypted = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
    }
    final initialData = CareData.fromJson(decrypted['data']);
    final references = Map<String, dynamic>.from(decrypted['files'] ?? {});
    final files = <String, RemoteAttachment>{};
    for (final id in initialData.records.expand(attachmentIds).toSet()) {
      if (references.containsKey(id)) {
        files[id] = RemoteAttachment.fromJson(references[id]);
      }
    }

    // 自动升级历史数据：将旧版临时短 ID 就地永久替换为云端真实 64 位 ID
    final migratedRecords = initialData.records.map((r) {
      final oldId = r.text('attachment');
      if (oldId.isNotEmpty && references.containsKey(oldId)) {
        final ref = RemoteAttachment.fromJson(references[oldId]);
        if (ref.parts.isNotEmpty && ref.parts.first != oldId) {
          final remoteId = ref.parts.first;
          files[remoteId] = ref;
          return r.copy(fields: {
            ...r.fields,
            'attachment': remoteId,
          });
        }
      }
      return r;
    }).toList();
    final data = initialData.copy(records: migratedRecords);
    return (
      data: data,
      revision: response['revision'] as int,
      files: files,
      wasEncrypted: wasEncrypted,
    );
  }

  Future<void> loadInto(
    LocalVault vault,
    ({
      CareData data,
      int revision,
      Map<String, RemoteAttachment> files,
      bool wasEncrypted,
    })
    snapshot, [
    String? password,
  ]) async {
    await vault.save(snapshot.data);
    vault.remoteOwner = this;
    vault.remoteAttachments.addAll(snapshot.files);
    vault.readRemote = (id, file) => readAttachment(id, file, password);
    revision = snapshot.revision;
  }

  Future<void> deleteAttachment(String id) async {
    final response = await http
        .delete(
          url.replace(path: '/api/v1/files/$id'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 404 && response.statusCode != 200) {
      check(response);
    }
  }

  Future<void> renameAttachment(String id, String newName) async {
    final response = await http
        .put(
          url.replace(path: '/api/v1/files/$id/rename'),
          headers: headers,
          body: jsonEncode({'filename': newName}),
        )
        .timeout(const Duration(seconds: 30));
    check(response);
  }

  Future<RemoteAttachment> uploadSingleAttachment(
    Stream<List<int>> source,
    String id, [
    String? filename,
  ]) => _upload(source, id, null, filename);

  Future<String> shareAttachment(String id) async {
    final response = check(
      await http
          .post(
            url.replace(path: '/api/v1/files/$id/share'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30)),
    );
    final shareUrl = response['url'] as String?;
    if (shareUrl == null || shareUrl.isEmpty) {
      throw StateError('生成分享链接失败');
    }
    return shareUrl;
  }
}
