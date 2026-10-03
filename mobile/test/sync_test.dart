import 'dart:convert';
import 'dart:typed_data';

import 'package:anban/data/models.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/services/sync.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('cloud saves records, settings and files; failures preserve confirmed state', () async {
    final source = await LocalVault.memory();
    final store = CareStore(source, CareData());
    final api = VaultSync('http://localhost:8080', 'session-token');
    const password = 'separate-backup-password';
    store.publish = (data, vault) => api.save(data, vault, password);
    final ids = <String>[];
    for (var i = 0; i < 9; i++) {
      ids.add(await source.addAttachment(Uint8List.fromList([3, 1, 4, 1, 5])));
    }
    final id = ids.first;
    dynamic saved;
    final objects = <String, dynamic>{};
    var revision = 0;
    var failWrite = false;
    await http.runWithClient(
      () async {
        await store.put(
          CareRecord(
            kind: 'weight',
            fields: {
              'weight': '55.5',
              'photos': jsonEncode([
                for (final id in ids) {'id': id, 'name': 'image.png'},
              ]),
            },
          ),
        );
        await store.profile({'name': '患者'});
        await store.settings({'largeText': 'true', 'token': 'legacy-token'});
        final decoded = await openBackup(
          Map<String, dynamic>.from(saved),
          password,
        );
        expect(decoded['data']['settings'], {'largeText': 'true'});
        expect(decoded['data']['profile']['name'], '患者');
        expect(
          objects,
          hasLength(9),
        ); // Unchanged attachments are not re-uploaded on each edit.
        final before = store.data.toJson();
        failWrite = true;
        await expectLater(store.profile({'name': '失败修改'}), throwsStateError);
        expect(store.data.toJson(), before);
        expect((await store.vault.load()).toJson(), before);
        await expectLater(store.clear(), throwsStateError);
        expect(store.data.toJson(), before);
        final replacement = {
          'data': before,
          'files': {
            for (final id in ids) id: base64Encode([9, 8, 7]),
          },
        };
        await expectLater(store.restore(replacement), throwsStateError);
        expect(await store.vault.attachment(id), [3, 1, 4, 1, 5]);
        failWrite = false;
        await store.restore(replacement);
        final pulled = await api.pull(password);
        final target = await LocalVault.memory();
        await api.loadInto(target, pulled, password);
        expect((await target.load()).profile['name'], '患者');
        expect(await target.attachment(id), [9, 8, 7]);
        await expectLater(
          api.pull('incorrect-password'),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
        expect(await target.attachment(id), [9, 8, 7]);
        await target.close();
        await store.clear();
        expect((await api.pull(password)).data.records, isEmpty);
      },
      () => MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer session-token');
        if (request.url.path == '/api/v1/files' && request.method == 'POST') {
          final remoteId = (objects.length + 1)
              .toRadixString(16)
              .padLeft(64, '0');
          objects[remoteId] = jsonDecode(request.body);
          return http.Response(jsonEncode({'id': remoteId}), 200);
        }
        if (request.url.path.startsWith('/api/v1/files/')) {
          return http.Response(
            jsonEncode(objects[request.url.pathSegments.last]),
            200,
          );
        }
        if (request.method == 'PUT') {
          if (failWrite) return http.Response('{"error":"save failed"}', 503);
          expect(request.headers['if-match'], '"$revision"');
          revision++;
          saved = jsonDecode(request.body);
          return http.Response(jsonEncode({'revision': revision}), 200);
        }
        return http.Response(
          jsonEncode({'revision': revision, 'data': saved}),
          200,
        );
      }),
    );
    store.dispose();
    await store.vault.close();
  });
}
