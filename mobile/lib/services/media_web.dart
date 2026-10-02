import 'dart:typed_data';

import 'package:video_player/video_player.dart';

Future<void> purgeMediaPreviews() async {}
Future<({VideoPlayerController controller, Future<void> Function() clean})>
videoSource(Uint8List bytes, String extension) async => (
  controller: VideoPlayerController.networkUrl(
    Uri.dataFromBytes(
      bytes,
      mimeType: extension == 'mov' ? 'video/quicktime' : 'video/mp4',
    ),
  ),
  clean: () async {},
);
