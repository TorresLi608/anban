import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../data/medical.dart';
import '../data/store.dart';
import '../services/media_source.dart';
import '../ui.dart';
import 'forms.dart';

Future<void> importMedia(
  BuildContext context,
  CareStore store,
  String kind, {
  bool camera = false,
}) async {
  await attempt(context, () async {
    Uint8List? bytes;
    String filename = '照片.jpg';
    if (camera) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (file == null) {
        return;
      }
      bytes = await file.readAsBytes();
      filename = file.name;
    } else {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: kind == 'document'
            ? ['pdf', 'jpg', 'jpeg', 'png', 'webp']
            : ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'mp3', 'm4a', 'wav'],
      );
      if (result == null) {
        return;
      }
      if ((await result.length() ?? 0) > 20 * 1024 * 1024) {
        throw const FormatException('单个附件最多 20 MB');
      }
      bytes = await result.readAsBytes();
      filename = result.name;
    }
    final attachment = await store.vault.addAttachment(bytes);
    if (!context.mounted) {
      return;
    }
    await editRecord(
      context,
      store,
      kind,
      initial: {
        'title': filename,
        'attachment': attachment,
        'filename': filename,
        'extension': filename.split('.').last.toLowerCase(),
        if (kind == 'document') 'category': classify(filename),
      },
    );
  });
}

String classify(String name) {
  final n = name.toLowerCase();
  if (n.contains('ct') || n.contains('mri')) {
    return 'CT / MRI 报告';
  }
  if (n.contains('验血') || n.contains('血常规')) {
    return '验血报告';
  }
  if (n.contains('出院')) {
    return '出院小结';
  }
  if (n.contains('医嘱')) {
    return '医嘱单';
  }
  if (n.contains('处方')) {
    return '处方单';
  }
  return '其他';
}

Future<void> previewMedia(
  BuildContext context,
  CareStore store,
  CareRecord record,
) async {
  if (record.text('attachment').isEmpty) {
    await editRecord(context, store, record.kind, record: record);
    return;
  }
  await attempt(context, () async {
    final bytes = await store.vault.attachment(record.text('attachment'));
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPreview(record: record, bytes: bytes),
      ),
    );
  });
}

class MediaPreview extends StatefulWidget {
  final CareRecord record;
  final Uint8List bytes;
  const MediaPreview({super.key, required this.record, required this.bytes});
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  final audio = AudioPlayer();
  VideoPlayerController? video;
  Future<void> Function()? clean;
  bool playing = false;
  String? error;
  String get ext => widget.record.text('extension');
  @override
  void initState() {
    super.initState();
    if (['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'].contains(ext)) {
      prepareVideo();
    }
    audio.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => playing = false);
      }
    });
  }

  Future<void> prepareVideo() async {
    try {
      final source = await videoSource(widget.bytes, ext);
      if (!mounted) {
        await source.controller.dispose();
        await source.clean();
        return;
      }
      video = source.controller;
      clean = source.clean;
      await video!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '当前设备无法预览此视频，文件仍已加密保存');
      }
    }
  }

  @override
  void dispose() {
    audio.dispose();
    final controller = video, cleanup = clean;
    if (controller != null) {
      controller.dispose().then((_) => cleanup?.call());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record.text('title')),
      actions: [
        if (widget.record.kind == 'document')
          IconButton(
            tooltip: '导出这份病历',
            onPressed: () => attempt(context, () async {
              if (!await confirm(
                context,
                '导出未加密副本？',
                '仅在需要交给医护时使用。导出的文件由你选择的位置或应用保管。',
                action: '导出',
              )) {
                return;
              }
              await FilePicker.saveFile(
                fileName: safeFileName(widget.record.text('filename')),
                bytes: widget.bytes,
              );
            }),
            icon: const Icon(Icons.ios_share),
          ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(child: Center(child: body())),
          if (widget.record.text('note').isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.record.text('note')),
            ),
        ],
      ),
    ),
  );
  Widget body() {
    if (error != null) {
      return Note(error!, urgent: true);
    }
    if ([
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'bmp',
      'heic',
      'heif',
    ].contains(ext)) {
      return InteractiveViewer(
        child: Image.memory(
          widget.bytes,
          errorBuilder: (_, _, _) => const Text('无法解码这张图片'),
        ),
      );
    }
    if (ext == 'pdf') {
      return PdfPreview(
        build: (_) => widget.bytes,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      );
    }
    if (['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'].contains(ext)) {
      if (video?.value.isInitialized != true) {
        return const CircularProgressIndicator();
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: video!.value.aspectRatio,
            child: VideoPlayer(video!),
          ),
          VideoProgressIndicator(video!, allowScrubbing: true),
          IconButton(
            tooltip: playing ? '暂停视频' : '播放视频',
            icon: Icon(
              playing ? Icons.pause_circle : Icons.play_circle,
              size: 48,
            ),
            onPressed: () async {
              if (playing) {
                await video!.pause();
              } else {
                await video!.play();
              }
              setState(() => playing = !playing);
            },
          ),
        ],
      );
    }
    if (!['mp3', 'm4a', 'wav', 'aac', 'ogg'].contains(ext)) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 64),
          SizedBox(height: 16),
          Text(
            '此格式暂不支持内置预览。文件已保存，可用右上角导出后通过对应软件查看。',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 70, color: pine),
        const SizedBox(height: 24),
        Text(widget.record.text('title')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => attempt(context, () async {
            if (playing) {
              await audio.pause();
            } else {
              await audio.play(BytesSource(widget.bytes));
            }
            setState(() => playing = !playing);
          }),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          label: Text(playing ? '暂停' : '播放留言'),
        ),
      ],
    );
  }
}
