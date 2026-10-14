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

  Widget _buildAudioTherapyCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF245B4B).withValues(alpha: 0.95),
            const Color(0xFF1B4539),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24245B4B),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    playing ? Icons.graphic_eq_rounded : Icons.spa_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安静一会儿 · 音疗舒缓',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '调低音量，让身心按自己的节奏放松休息',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (playing)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_up_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('播放中', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 音源选择
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.air_rounded, size: 16),
                  label: const Text('柔和白噪音'),
                  selected: sound == 'soft-noise.wav',
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(
                    color: sound == 'soft-noise.wav' ? pine : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: sound == 'soft-noise.wav' ? Colors.white : Colors.white24,
                  ),
                  onSelected: playing
                      ? null
                      : (_) => setState(() => sound = 'soft-noise.wav'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.music_note_rounded, size: 16),
                  label: const Text('缓慢和音'),
                  selected: sound == 'soft-tones.wav',
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(
                    color: sound == 'soft-tones.wav' ? pine : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: sound == 'soft-tones.wav' ? Colors.white : Colors.white24,
                  ),
                  onSelected: playing
                      ? null
                      : (_) => setState(() => sound = 'soft-tones.wav'),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 定时时长选择
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '定时停止播放',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final m in [5, 15, 30, 60]) ...[
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: playing ? null : () => setState(() => minutes = m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: minutes == m
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: minutes == m ? Colors.white70 : Colors.transparent,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$m 分钟',
                              style: TextStyle(
                                color: minutes == m ? Colors.white : Colors.white70,
                                fontSize: 12.5,
                                fontWeight: minutes == m ? FontWeight.w700 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (m != 60) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 播放操作大按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => attempt(context, toggleAudio),
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 22),
                label: Text(
                  playing ? '停止播放 · 闭目静歇' : '开启舒缓音疗',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: playing ? const Color(0xFFD6E8E2) : Colors.white,
                  foregroundColor: pine,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                '音频随安伴离线内置，无需消耗流量，支持后台伴随播放',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreathingGuideCard() {
    return Surface(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: pine.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.self_improvement_rounded, color: pine, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '深呼吸 · 让注意力慢下来',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: pine,
                      ),
                    ),
                    Text(
                      '平稳心率，缓解就医焦虑与身体紧绷',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 双重呼吸动效水波纹
          AnimatedBuilder(
            animation: breathing,
            builder: (_, _) {
              final val = breathing.value;
              final isExpanding = breathing.status == AnimationStatus.forward;
              final statusText = isExpanding
                  ? (val < 0.7 ? '慢慢吸气… 腹部微微隆起' : '微闭双眼… 感受宁静')
                  : (val > 0.3 ? '缓缓呼气… 释放所有紧绷' : '放松双肩… 自然等待');

              return Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外层扩散波纹
                      Container(
                        width: 140 + val * 40,
                        height: 140 + val * 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pine.withValues(alpha: 0.05 + val * 0.07),
                        ),
                      ),
                      // 中层波纹
                      Container(
                        width: 110 + val * 24,
                        height: 110 + val * 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pine.withValues(alpha: 0.12 + val * 0.08),
                        ),
                      ),
                      // 核心内圈
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              pine.withValues(alpha: 0.85),
                              pine,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: pine.withValues(alpha: 0.3),
                              blurRadius: 12 + val * 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          breathing.isAnimating
                              ? (isExpanding ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
                              : Icons.spa_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    breathing.isAnimating ? statusText : '放松肩膀，自然呼吸\n不必屏气，随舒适节奏即可',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: breathing.isAnimating ? pine : muted,
                      fontSize: 14,
                      fontWeight: breathing.isAnimating ? FontWeight.w700 : FontWeight.normal,
                      height: 1.6,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // 呼吸引导开关
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                if (breathing.isAnimating) {
                  breathing.stop();
                } else if (!MediaQuery.disableAnimationsOf(context)) {
                  breathing.repeat(reverse: true);
                }
                setState(() {});
              },
              icon: Icon(breathing.isAnimating ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(breathing.isAnimating ? '停止引导' : '开始放松练习'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '若有胸闷、头晕或气促不适，请立即停止练习并联系医护人员。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memories = widget.store.records('memory');
    final moods = widget.store.records('mood');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('TOGETHER', '留一点时间，给彼此', '陪伴可以是一句话，也可以是安静地坐在一起。'),
        ResponsiveColumns(
          main: Column(
            children: [
              // 1. 白噪音音疗舒缓舱
              _buildAudioTherapyCard(),
              const SizedBox(height: 24),

              // 2. 我们的时光
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: pine.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.favorite_outline_rounded, color: pine, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '我们的时光',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: pine,
                                ),
                              ),
                              Text(
                                '一张照片、一段声音，或一句想说的话',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
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
                            PopupMenuItem(
                              value: 'text',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 18, color: pine),
                                  SizedBox(width: 8),
                                  Text('写一篇日记'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'file',
                              child: Row(
                                children: [
                                  Icon(Icons.attach_file_rounded, size: 18, color: pine),
                                  SizedBox(width: 8),
                                  Text('导入照片 / 视频 / 语音'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'camera',
                              child: Row(
                                children: [
                                  Icon(Icons.camera_alt_outlined, size: 18, color: pine),
                                  SizedBox(width: 8),
                                  Text('拍一张照片'),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: pine.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 16, color: pine),
                                SizedBox(width: 4),
                                Text(
                                  '留下一笔',
                                  style: TextStyle(
                                    color: pine,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Note('所有回忆与照片均加密保存于专属空间，可在“我的”导出带密码备份。'),
                    const SizedBox(height: 16),

                    // 快捷录音卡片
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: recording ? danger.withValues(alpha: 0.08) : const Color(0xFFF3F7F2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: recording ? danger.withValues(alpha: 0.3) : const Color(0xFFE2EBE0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: recording ? danger : pine,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recording ? '正在录音中… (最长 2 分钟)' : '录一段温暖语音留言',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: recording ? danger : pine,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  recording ? '点击右侧按钮即可完成并加密保存' : '把想说给家人或患者的心里话保存下来',
                                  style: const TextStyle(color: muted, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: working ? null : recordVoice,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: recording ? danger : pine),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              working
                                  ? '处理中…'
                                  : recording
                                  ? '完成保存'
                                  : '开始录音',
                              style: TextStyle(
                                color: recording ? danger : pine,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (memories.isEmpty)
                      const EmptyState(
                        Icons.photo_album_outlined,
                        '今天，有什么想留下的？',
                        '一张温馨照片、一段真挚录音，或一句想说给彼此的话。',
                      )
                    else
                      for (final m in memories)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE7EDE5)),
                          ),
                          child: InkWell(
                            onTap: () => previewMedia(context, widget.store, m),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: pine.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    m.text('attachment').isEmpty
                                        ? Icons.edit_note_rounded
                                        : Icons.perm_media_rounded,
                                    color: pine,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              m.text('title'),
                                              style: const TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                                color: pine,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            dayKey(m.at),
                                            style: const TextStyle(color: muted, fontSize: 11.5),
                                          ),
                                        ],
                                      ),
                                      if (m.text('note').isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          m.text('note'),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: muted, fontSize: 12.5, height: 1.5),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                RecordActions(
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
                              ],
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
              // 3. 此刻，你还好吗
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: pine.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.mood_rounded, color: pine, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '此刻，你还好吗',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: pine,
                                ),
                              ),
                              Text(
                                '累了可以休息，也可以请家人接一班',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => editRecord(context, widget.store, 'mood'),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('记心情', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (moods.isEmpty)
                      const Text(
                        '记录下这一刻的心情，无论是平静、有些疲惫还是想要倾诉，安伴都在这里。',
                        style: TextStyle(color: muted, fontSize: 12.5, height: 1.6),
                      )
                    else
                      for (final m in moods.take(4))
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8F5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE6EFE4)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: pine.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  m.text('role').isEmpty ? '照护记录' : m.text('role'),
                                  style: const TextStyle(
                                    color: pine,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.text('mood'),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    if (m.text('note').isNotEmpty)
                                      Text(
                                        m.text('note'),
                                        style: const TextStyle(color: muted, fontSize: 11.5),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                dayKey(m.at),
                                style: const TextStyle(color: muted, fontSize: 11),
                              ),
                              RecordActions(
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
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 4. 呼吸引导仪
              _buildBreathingGuideCard(),
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
