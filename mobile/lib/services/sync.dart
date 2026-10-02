import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/vault.dart';

class VaultSync {
  final Uri url;
  final String token;
  int revision = 0;
  LocalVault? _source;
  Map<String, String> references = {};
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
                ].contains(uri.host))) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请使用 HTTPS 服务地址；本机调试可使用 HTTP');
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
      throw StateError(message);
    }
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(r.bodyBytes)) as Map,
    );
  }

  Future<void> save(CareData data, LocalVault vault, String password) async {
    final files = <String, String>{};
    int total = 0;
    for (final id in data.records.expand(attachmentIds).toSet()) {
      if (id.isEmpty || files.containsKey(id)) continue;
      final bytes = await vault.attachment(id);
      total += bytes.length;
      if (total > 100 * 1024 * 1024) throw StateError('附件合计超过 100 MB，请分批整理后同步');
      if (identical(_source, vault) && references.containsKey(id)) {
        files[id] = references[id]!;
        continue;
      }
      final encryptedFile = await sealBackup({
        'file': base64Encode(bytes),
      }, password);
      final response = check(
        await http
            .post(
              url.replace(path: '/api/v1/files'),
              headers: headers,
              body: jsonEncode(encryptedFile),
            )
            .timeout(const Duration(seconds: 120)),
      );
      files[id] = response['id'] as String;
    }
    final encrypted = await sealBackup({
      'data': {
        ...data.toJson(),
        'settings': {
          for (final e in data.settings.entries)
            if (!['token', 'server'].contains(e.key) &&
                !e.key.startsWith('revision:'))
              e.key: e.value,
        },
      },
      'files': files,
    }, password);
    final body = jsonEncode(encrypted);
    if (utf8.encode(body).length > 12 * 1024 * 1024) {
      throw StateError('快照过大，请使用本地备份');
    }
    final response = check(
      await http
          .put(
            url,
            headers: {...headers, 'If-Match': '"$revision"'},
            body: body,
          )
          .timeout(const Duration(seconds: 30)),
    );
    revision = response['revision'] as int;
    references = files;
    _source = vault;
  }

  Future<({CareData data, int revision, Map<String, String> files})> pull(
    String password, {
    bool allowEmpty = false,
  }) async {
    final response = check(
      await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30)),
    );
    if (response['data'] == null) {
      if (!allowEmpty) throw StateError('服务器还没有备份');
      revision = response['revision'] as int;
      this.references = {};
      return (data: CareData(), revision: revision, files: <String, String>{});
    }
    final decrypted = await openBackup(
      Map<String, dynamic>.from(response['data']),
      password,
    );
    final data = CareData.fromJson(decrypted['data']);
    final references = Map<String, String>.from(decrypted['files'] ?? {});
    final files = <String, String>{};
    int total = 0;
    for (final id in data.records.expand(attachmentIds).toSet()) {
      if (id.isEmpty || files.containsKey(id)) continue;
      final remote = references[id];
      if (remote == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(remote)) {
        throw const FormatException('远端快照缺少附件');
      }
      final response = check(
        await http
            .get(url.replace(path: '/api/v1/files/$remote'), headers: headers)
            .timeout(const Duration(seconds: 120)),
      );
      final file = await openBackup(response, password);
      final content = file['file'] as String;
      final size = base64Decode(content).length;
      total += size;
      if (size > 20 * 1024 * 1024 || total > 100 * 1024 * 1024) {
        throw const FormatException('附件超出恢复上限（单个 20 MB，合计 100 MB）');
      }
      files[id] = content;
    }
    revision = response['revision'] as int;
    this.references = references;
    return (data: data, revision: revision, files: files);
  }
}
