import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'image_preview_page.dart';
import '../core/audio_duration.dart';

class RecordMediaView extends StatefulWidget {
  const RecordMediaView({
    super.key,
    this.image,
    this.audio,
    this.compact = false,
    this.duration,
    this.onError,
  });
  final String? image, audio;
  final bool compact;
  final Duration? duration;
  final ValueChanged<String>? onError;
  @override
  State<RecordMediaView> createState() => _RecordMediaViewState();
}

class _RecordMediaViewState extends State<RecordMediaView> {
  AudioPlayer? player;
  StreamSubscription<PlayerException>? errorSubscription;
  String? error;
  bool loading = false;
  Duration? fileDuration;

  @override
  void initState() {
    super.initState();
    loadDuration();
  }

  Future<void> loadDuration() async {
    final path = widget.audio;
    fileDuration = widget.duration;
    if (path == null || fileDuration != null) return;
    final value = await readWaveDuration(path);
    if (mounted && widget.audio == path) setState(() => fileDuration = value);
  }

  @override
  void dispose() {
    errorSubscription?.cancel();
    player?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RecordMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      errorSubscription?.cancel();
      player?.dispose();
      player = null;
      error = null;
      loading = false;
      loadDuration();
    }
  }

  Future<void> toggle() async {
    AudioPlayer? active;
    try {
      if (player == null) {
        setState(() {
          loading = true;
          error = null;
        });
        active = AudioPlayer();
        player = active;
        errorSubscription = active.errorStream.listen((e) {
          if (mounted && identical(active, player)) {
            setState(() => error = '播放失败：$e');
            widget.onError?.call('播放失败：$e');
          }
        });
        await active.setFilePath(widget.audio!);
        if (!mounted || !identical(active, player)) return;
        setState(() => loading = false);
      }
      active = player;
      if (active == null || !mounted) return;
      if (active.playing &&
          active.processingState != ProcessingState.completed) {
        await active.pause();
      } else {
        if (active.processingState == ProcessingState.completed) {
          await active.seek(Duration.zero);
        }
        if (!mounted || !identical(active, player)) return;
        unawaited(
          active.play().catchError((Object e) {
            if (mounted && identical(active, player)) {
              setState(() => error = '播放失败：$e');
              widget.onError?.call('播放失败：$e');
            }
          }),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted || !identical(active, player)) return;
      errorSubscription?.cancel();
      player?.dispose();
      setState(() {
        player = null;
        loading = false;
        error = '无法播放音频：$e';
      });
      widget.onError?.call('无法播放音频：$e');
    }
  }

  String formatTime(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.image != null)
        InkWell(
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ImagePreviewPage(path: widget.image!),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(widget.image!),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Text('图片文件不可用'),
            ),
          ),
        ),
      if (widget.audio != null)
        SizedBox(
          width: widget.compact ? 164 : 204,
          child: Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: player?.playerStateStream,
                builder: (context, snapshot) {
                  final playing =
                      snapshot.data?.playing == true &&
                      snapshot.data?.processingState !=
                          ProcessingState.completed;
                  return IconButton(
                    tooltip: loading
                        ? '正在打开音频'
                        : playing
                        ? '暂停录音'
                        : '播放录音',
                    onPressed: loading ? null : toggle,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  );
                },
              ),
              Expanded(
                child: StreamBuilder<Duration?>(
                  stream: player?.durationStream,
                  builder: (context, durationSnapshot) => StreamBuilder<Duration>(
                    stream: player?.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration =
                          durationSnapshot.data ??
                          player?.duration ??
                          fileDuration ??
                          Duration.zero;
                      final maximum = duration.inMilliseconds;
                      return Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              label: '播放进度',
                              value:
                                  '${formatTime(position)} / ${formatTime(duration)}',
                              child: LinearProgressIndicator(
                                value: maximum > 0
                                    ? (position.inMilliseconds / maximum).clamp(
                                        0.0,
                                        1.0,
                                      )
                                    : 0,
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(3),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.18),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StreamBuilder<PlayerState>(
                            stream: player?.playerStateStream,
                            builder: (context, state) {
                              final completed =
                                  state.data?.processingState ==
                                  ProcessingState.completed;
                              final remaining = completed
                                  ? maximum
                                  : (maximum - position.inMilliseconds).clamp(
                                      0,
                                      maximum,
                                    );
                              return Text(
                                maximum > 0
                                    ? '${(remaining / 1000).ceil()}s'
                                    : '—s',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      if (error != null && !widget.compact)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
