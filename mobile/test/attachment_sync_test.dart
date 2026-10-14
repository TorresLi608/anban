import 'dart:convert';
import 'dart:typed_data';

import 'package:anban/data/attachments.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/services/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'chunked attachments load lazily, reuse uploads and handle multi-part files',
    () async {
      final source = await LocalVault.memory();
      final bytes = Uint8List(attachmentChunkBytes + 19)
        ..[0] = 42
        ..[attachmentChunkBytes] = 99;
      final id = await source.addAttachmentStream(
        Stream.fromIterable([bytes.sublist(0, 123), bytes.sublist(123)]),
      );
      final data = CareData(
        records: [
          CareRecord(
            kind: 'document',
            fields: {'title': '影像视频', 'attachment': id},
          ),
        ],
      );
      final api = VaultSync('http://localhost:8080', 'token');
      final objects = <String, dynamic>{};
      dynamic snapshot;
      var reads = 0, revision = 0;
      await http.runWithClient(
        () async {
          await api.save(data, source);
          expect(objects, hasLength(2));
          await api.save(data, source);
          expect(objects, hasLength(2));
          expect(reads, 0);
          final pulled = await api.pull();
          expect(reads, 0);
          final target = await LocalVault.memory();
          await api.loadInto(target, pulled);
          expect(reads, 0);
          final restored = await target.attachment(id);
          expect(reads, 2);
          expect(restored.length, bytes.length);
          expect(restored[0], 42);
          expect(restored[attachmentChunkBytes], 99);
          await target.attachment(id);
          expect(reads, 2);
          final original = pulled.files[id]!;
          expect(
            () => RemoteAttachment.fromJson({
              'chunks': original.parts,
              'size': maxAttachmentBytes + 1,
            }),
            throwsFormatException,
          );
          await target.close();
        },
        () => MockClient((r) async {
          if (r.url.path == '/api/v1/files' && r.method == 'POST') {
            final id = (objects.length + 1).toRadixString(16).padLeft(64, '0');
            objects[id] = jsonDecode(r.body);
            return http.Response(jsonEncode({'id': id}), 200);
          }
          if (r.url.path.startsWith('/api/v1/files/')) {
            reads++;
            return http.Response(
              jsonEncode(objects[r.url.pathSegments.last]),
              200,
            );
          }
          if (r.method == 'PUT') {
            expect(r.headers['if-match'], '"$revision"');
            snapshot = jsonDecode(r.body);
            return http.Response(jsonEncode({'revision': ++revision}), 200);
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode({'revision': revision, 'data': snapshot})),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await source.close();
    },
  );

  test(
    'legacy v1 snapshots and attachment envelopes remain readable',
    () async {
      final remoteId = 'a' * 64;
      final data = CareData(
        records: [
          CareRecord(
            id: 'legacy-doc',
            kind: 'document',
            fields: {'title': '旧病历', 'attachment': 'old-file'},
          ),
        ],
      );
      final salt = randomBytes(16);
      final key = await passwordKey('abc123', salt);
      final e = await encryptBytes(
        utf8.encode(
          jsonEncode({
            'data': {...data.toJson(), 'version': 1},
            'files': {'old-file': remoteId},
          }),
        ),
        key,
      );
      final snapshot = {
        'version': 1,
        'algorithm': 'AES-256-GCM',
        'iterations': 210000,
        'salt': base64Encode(salt),
        ...e,
      };
      final fileSalt = randomBytes(16);
      final fileKey = await passwordKey('abc123', fileSalt);
      final fileEncrypted = await encryptBytes(
        utf8.encode(jsonEncode({'file': base64Encode([1, 2, 3])})),
        fileKey,
      );
      final file = {
        'version': 1,
        'algorithm': 'AES-256-GCM',
        'iterations': 210000,
        'salt': base64Encode(fileSalt),
        ...fileEncrypted,
      };
      final api = VaultSync('http://localhost:8080', 'token');
      await http.runWithClient(
        () async {
          final pulled = await api.pull('abc123');
          final vault = await LocalVault.memory();
          await api.loadInto(vault, pulled, 'abc123');
          expect(await vault.attachment('old-file'), [1, 2, 3]);
          await vault.close();
        },
        () => MockClient(
          (r) async => http.Response.bytes(
            utf8.encode(
              jsonEncode(
                r.url.path.contains('/files/')
                    ? file
                    : {'revision': 1, 'data': snapshot},
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    },
  );

  test('LocalVault preserves and updates attachment filename', () async {
    final vault = await LocalVault.memory();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final id = await vault.addAttachment(bytes, filename: '化验报告.pdf');
    expect(await vault.attachmentName(id), '化验报告.pdf');

    await vault.renameAttachment(id, '化验报告_修改.pdf');
    expect(await vault.attachmentName(id), '化验报告_修改.pdf');
    expect(await vault.attachment(id), bytes);
    await vault.close();
  });

  test('VaultSync supports rename, delete and share operations', () async {
    final api = VaultSync('http://localhost:8080', 'test-token');
    final recordedRequests = <http.Request>[];

    await http.runWithClient(
      () async {
        // 测试重命名
        await api.renameAttachment('file-123', '新报告.pdf');
        expect(recordedRequests.last.method, 'PUT');
        expect(recordedRequests.last.url.path, '/api/v1/files/file-123/rename');
        final renameBody = jsonDecode(recordedRequests.last.body) as Map;
        expect(renameBody['filename'], '新报告.pdf');

        // 测试分享链接生成
        final shareUrl = await api.shareAttachment('file-123');
        expect(recordedRequests.last.method, 'POST');
        expect(recordedRequests.last.url.path, '/api/v1/files/file-123/share');
        expect(shareUrl, 'http://localhost:8080/api/v1/share/mock-share-token');

        // 测试删除 MinIO 源文件
        await api.deleteAttachment('file-123');
        expect(recordedRequests.last.method, 'DELETE');
        expect(recordedRequests.last.url.path, '/api/v1/files/file-123');
      },
      () => MockClient((r) async {
        final req = http.Request(r.method, r.url)..headers.addAll(r.headers);
        if (r.body.isNotEmpty) {
          req.body = r.body;
        }
        recordedRequests.add(req);

        if (r.method == 'PUT' && r.url.path.endsWith('/rename')) {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        if (r.method == 'POST' && r.url.path.endsWith('/share')) {
          return http.Response(
            jsonEncode({
              'token': 'mock-share-token',
              'url': 'http://localhost:8080/api/v1/share/mock-share-token',
            }),
            200,
          );
        }
        if (r.method == 'DELETE') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not Found', 404);
      }),
    );
  });
}
