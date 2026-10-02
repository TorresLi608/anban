import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> purgeMediaPreviews() async {
  final dir = Directory(
    '${(await getTemporaryDirectory()).path}/anban-previews',
  );
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<({VideoPlayerController controller, Future<void> Function() clean})>
videoSource(Uint8List bytes, String extension) async {
  final dir = await Directory(
    '${(await getTemporaryDirectory()).path}/anban-previews',
  ).create(recursive: true);
  final file = File(
    '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  return (
    controller: VideoPlayerController.file(file),
    clean: () async {
      if (await file.exists()) {
        await file.delete();
      }
    },
  );
}
