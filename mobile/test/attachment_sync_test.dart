import 'dart:convert';
import 'dart:typed_data';

import 'package:anban/data/attachments.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/services/sync.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'chunked attachments load lazily, reuse uploads and reject reordered parts',
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
          await api.save(data, source, 'abc123');
          expect(objects, hasLength(2));
          await api.save(data, source, 'abc123');
          expect(objects, hasLength(2));
          expect(reads, 0);
          final pulled = await api.pull('abc123');
          expect(reads, 0);
          final target = await LocalVault.memory();
          await api.loadInto(target, pulled, 'abc123');
          expect(reads, 0);
          final restored = await target.attachment(id);
          expect(reads, 2);
          expect(restored.length, bytes.length);
          expect(restored[0], 42);
          expect(restored[attachmentChunkBytes], 99);
          await target.attachment(id);
          expect(reads, 2);
          final original = pulled.files[id]!;
          final swapped = RemoteAttachment(
            original.parts.reversed.toList(),
            size: original.size,
            salt: original.salt,
          );
          await expectLater(
            api.readAttachment(id, swapped, 'abc123').toList(),
            throwsA(isA<SecretBoxAuthenticationError>()),
          );
          expect(
            () => RemoteAttachment.fromJson({
              'chunks': original.parts,
              'size': maxAttachmentBytes + 1,
              'salt': original.salt,
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
          return http.Response(
            jsonEncode({'revision': revision, 'data': snapshot}),
            200,
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
      final snapshot = await sealBackup({
        'data': {...data.toJson(), 'version': 1},
        'files': {'old-file': remoteId},
      }, 'abc123');
      final file = await sealBackup({
        'file': base64Encode([1, 2, 3]),
      }, 'abc123');
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
          (r) async => http.Response(
            jsonEncode(
              r.url.path.contains('/files/')
                  ? file
                  : {'revision': 1, 'data': snapshot},
            ),
            200,
          ),
        ),
      );
    },
  );
}
