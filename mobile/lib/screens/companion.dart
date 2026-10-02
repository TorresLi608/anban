import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../ui.dart';
import 'forms.dart';
import 'media.dart';

class CompanionPage extends StatefulWidget {
  final CareStore store;
  const CompanionPage({super.key, required this.store});
  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage>
    with SingleTickerProviderStateMixin {
  AudioPlayer? _player;
  AudioRecorder? _recorder;
  AudioPlayer get player => _player ??= AudioPlayer();
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  late AnimationController breathing;
  Timer? shutoff, recordLimit;
  bool playing = false, recording = false, working = false;
  int minutes = 15;
  String sound = 'soft-noise.wav';
  BytesBuilder? pcm;
  Completer<void>? recorded;
  @override
  void initState() {
    super.initState();
    breathing = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  void dispose() {
    shutoff?.cancel();
    recordLimit?.cancel();
    breathing.dispose();
    _player?.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> toggleAudio() async {
    if (playing) {
      await player.stop();
      shutoff?.cancel();
      setState(() => playing = false);
      return;
    }
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(.25);
    await player.play(AssetSource(sound));
    setState(() => playing = true);
    shutoff?.cancel();
    shutoff = Timer(Duration(minutes: minutes), () async {
      await player.stop();
      if (mounted) {
        setState(() => playing = false);
      }
    });
  }

  Future<void> recordVoice() async {
    if (working) {
      return;
    }
    setState(() => working = true);
    try {
      if (!recording) {
        if (!await recorder.hasPermission()) {
          throw StateError('请允许麦克风权限后再录音');
        }
        pcm = BytesBuilder();
        recorded = Completer<void>();
        final stream = await recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        stream.listen(
          (chunk) => pcm?.add(chunk),
          onDone: () {
            if (recorded?.isCompleted == false) {
              recorded!.complete();
            }
          },
          onError: (Object error) {
            if (recorded?.isCompleted == false) {
              recorded!.completeError(error);
            }
          },
        );
        if (mounted) {
          setState(() => recording = true);
        }
        recordLimit = Timer(const Duration(minutes: 2), () {
          if (mounted && recording) {
            recordVoice();
          }
        });
      } else {
        recordLimit?.cancel();
        await recorder.stop();
        await recorded!.future.timeout(const Duration(seconds: 5));
        final bytes = wav(pcm!.takeBytes());
        final attachment = await widget.store.vault.addAttachment(bytes);
        if (mounted) {
          setState(() => recording = false);
          await editRecord(
            context,
            widget.store,
            'memory',
            initial: {
              'title': '一段语音留言',
              'attachment': attachment,
              'extension': 'wav',
              'filename': '留言.wav',
            },
          );
        }
      }
    } catch (e) {
      await recorder.cancel();
      if (mounted) {
        setState(() => recording = false);
        toast(context, e.toString());
      }
    }
    if (mounted) {
      setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memories = widget.store.records('memory'),
        moods = widget.store.records('mood');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('TOGETHER', '留一点时间，给彼此', '陪伴可以是一句话，也可以是安静地坐在一起。'),
        ResponsiveColumns(
          main: Column(
            children: [
              Surface(
                color: const Color(0xFFE6EBE4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '安静一会儿',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        color: pine,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '调低音量，让身体按自己的节奏休息。',
                      style: TextStyle(color: pine, height: 1.7),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('柔和白噪音'),
                          selected: sound == 'soft-noise.wav',
                          onSelected: playing
                              ? null
                              : (_) => setState(() => sound = 'soft-noise.wav'),
                        ),
                        ChoiceChip(
                          label: const Text('缓慢和音'),
                          selected: sound == 'soft-tones.wav',
                          onSelected: playing
                              ? null
                              : (_) => setState(() => sound = 'soft-tones.wav'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 18,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => attempt(context, toggleAudio),
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          label: Text(playing ? '停止播放' : '开始播放'),
                        ),
                        DropdownButton<int>(
                          value: minutes,
                          underline: const SizedBox(),
                          items: [
                            for (final m in [5, 15, 30, 60])
                              DropdownMenuItem(
                                value: m,
                                child: Text(
                                  '$m 分钟后停止',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: playing
                              ? null
                              : (v) => setState(() => minutes = v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '音频随应用提供，可离线播放。',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Section(
                '我们的时光',
                trailing: PopupMenuButton<String>(
                  tooltip: '留下回忆',
                  onSelected: (v) {
                    if (v == 'text') {
                      editRecord(context, widget.store, 'memory');
                    } else {
                      importMedia(
                        context,
                        widget.store,
                        'memory',
                        camera: v == 'camera',
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'text', child: Text('写一篇日记')),
                    PopupMenuItem(value: 'file', child: Text('导入照片 / 视频 / 语音')),
                    PopupMenuItem(value: 'camera', child: Text('拍一张照片')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18, color: pine),
                        SizedBox(width: 6),
                        Text('留下一笔', style: TextStyle(color: pine)),
                      ],
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    const Note('回忆和附件加密后自动保存到云端。可在“我的”手动导出带密码的备份。'),
                    const SizedBox(height: 12),
                    if (memories.isEmpty)
                      const EmptyState(
                        Icons.photo_album_outlined,
                        '今天，有什么想留下的？',
                        '一张照片、一段声音，或一句想说的话。',
                      ),
                    for (final m in memories)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        leading: Icon(
                          m.text('attachment').isEmpty
                              ? Icons.edit_note
                              : Icons.perm_media_outlined,
                          color: pine,
                        ),
                        title: Text(m.text('title')),
                        subtitle: Text(
                          '${dayKey(m.at)}\n${m.text('note')}',
                          maxLines: 3,
                        ),
                        onTap: () => previewMedia(context, widget.store, m),
                        trailing: RecordActions(
                          edit: () => editRecord(
                            context,
                            widget.store,
                            'memory',
                            record: m,
                          ),
                          delete: () => attempt(
                            context,
                            () => deleteRecord(context, widget.store, m),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: working ? null : recordVoice,
                        icon: Icon(recording ? Icons.stop : Icons.mic_none),
                        label: Text(
                          working
                              ? '处理中…'
                              : recording
                              ? '结束并保存录音'
                              : '录一段留言 · 最长 2 分钟',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          aside: Column(
            children: [
              Section(
                '此刻，你还好吗',
                trailing: TextButton(
                  onPressed: () => editRecord(context, widget.store, 'mood'),
                  child: const Text('记心情'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '累了可以休息，也可以请家人接一班。',
                      style: TextStyle(fontSize: 18, height: 1.7),
                    ),
                    const SizedBox(height: 16),
                    for (final m in moods.take(4))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${m.text('role')} · ${m.text('mood')}'),
                        subtitle: Text('${dayKey(m.at)} ${m.text('note')}'),
                        trailing: RecordActions(
                          edit: () => editRecord(
                            context,
                            widget.store,
                            'mood',
                            record: m,
                          ),
                          delete: () => attempt(
                            context,
                            () => deleteRecord(context, widget.store, m),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Section(
                '让注意力慢下来',
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: breathing,
                      builder: (_, _) => Container(
                        width: 120 + breathing.value * 20,
                        height: 120 + breathing.value * 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pine.withValues(alpha: .10),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.spa_outlined,
                          size: 36,
                          color: pine,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '放松肩膀，自然呼吸。\n不必屏气，也不必跟随固定速度。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, height: 1.8, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () {
                        if (breathing.isAnimating) {
                          breathing.stop();
                        } else if (!MediaQuery.disableAnimationsOf(context)) {
                          breathing.repeat(reverse: true);
                        }
                        setState(() {});
                      },
                      child: Text(breathing.isAnimating ? '停止引导' : '开始放松'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '若有气促、胸闷或头晕，请停止练习并联系医护。',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Uint8List wav(Uint8List pcm) {
  final out = Uint8List(44 + pcm.length), d = ByteData.view(out.buffer);
  void tag(int offset, String value) =>
      out.setRange(offset, offset + value.length, value.codeUnits);
  tag(0, 'RIFF');
  d.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, 16000, Endian.little);
  d.setUint32(28, 32000, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  d.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, out.length, pcm);
  return out;
}
