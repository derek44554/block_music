import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/connection_provider.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

class PlayerScreen extends StatefulWidget {
  final Song song;
  const PlayerScreen({super.key, required this.song});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotateCtrl;
  bool _isShuffle = false;
  int _repeatMode = 0;
  bool _seeking = false;
  double _seekValue = 0;
  late Song _currentSong;

  // 下滑关闭
  double _dragOffset = 0;
  static const _dismissThreshold = 120.0;

  AudioService get _audio => AudioService.instance;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _rotateCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12));

    // 监听播放状态驱动旋转动画
    _audio.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        _rotateCtrl.repeat();
      } else {
        _rotateCtrl.stop();
      }
    });
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Color(int.parse('FF${_currentSong.coverColor}', radix: 16));
    return Scaffold(
      body: GestureDetector(
        onVerticalDragUpdate: (d) {
          if (d.delta.dy > 0) {
            setState(() => _dragOffset += d.delta.dy);
          }
        },
        onVerticalDragEnd: (d) {
          if (_dragOffset > _dismissThreshold ||
              (d.primaryVelocity ?? 0) > 800) {
            Navigator.pop(context);
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: AnimatedSlide(
          offset: Offset(0, _dragOffset / MediaQuery.of(context).size.height),
          duration: _dragOffset == 0
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          curve: Curves.easeOut,
          child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.withValues(alpha: 0.6), AppTheme.bg, AppTheme.bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 拖动指示条
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _buildTopBar(context),
              const Spacer(),
              _buildAlbumArt(c),
              const Spacer(),
              _buildSongInfo(),
              const SizedBox(height: 20),
              _buildProgressBar(),
              const SizedBox(height: 16),
              _buildControls(),
              const SizedBox(height: 12),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
            Column(
              children: [
                const Text('正在播放',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        letterSpacing: 2)),
                Text(widget.song.title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),              ],
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 28),
              onPressed: () {},
            ),
          ],
        ),
      );

  Widget _buildAlbumArt(Color c) => Center(
        child: AnimatedBuilder(
          animation: _rotateCtrl,
          builder: (_, child) => Transform.rotate(
            angle: _rotateCtrl.value * 2 * 3.14159,
            child: child,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = (MediaQuery.of(context).size.width * 0.6).clamp(180.0, 260.0);
              return Container(
                width: size,
                height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c, c.withValues(alpha: 0.3), AppTheme.card],
                stops: const [0.4, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                    color: c.withValues(alpha: 0.5),
                    blurRadius: 40,
                    spreadRadius: 10),
              ],
            ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.music_note,
                      color: Colors.white.withValues(alpha: 0.6), size: size * 0.3),
                  Container(
                    width: size * 0.23,
                    height: size * 0.23,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.bg,
                      border: Border.all(color: AppTheme.surface, width: 4),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      );

  Widget _buildSongInfo() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _currentSong.title,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _buildProgressBar() {
    return StreamBuilder<Duration?>(
      stream: _audio.durationStream,
      builder: (_, durSnap) {
        final total = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: _audio.positionStream,
          builder: (_, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final progress = total.inMilliseconds > 0
                ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;
            final displayProgress = _seeking ? _seekValue : progress;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.surface,
                      thumbColor: Colors.white,
                      overlayColor: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: displayProgress.toDouble(),
                      onChangeStart: (_) => setState(() => _seeking = true),
                      onChanged: (v) => setState(() => _seekValue = v),
                      onChangeEnd: (v) {
                        setState(() => _seeking = false);
                        final target = Duration(
                            milliseconds: (v * total.inMilliseconds).round());
                        _audio.seek(target);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _seeking
                              ? _fmt(Duration(
                                  milliseconds: (_seekValue *
                                          total.inMilliseconds)
                                      .round()))
                              : _fmt(position),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        Text(_fmt(total),
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<PlayerState>(
      stream: _audio.playerStateStream,
      builder: (_, snap) {
        final state = snap.data;
        final isPlaying = state?.playing ?? false;
        final isLoading = state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: _isShuffle
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    size: 24),
                onPressed: () => setState(() => _isShuffle = !_isShuffle),
              ),
              IconButton(
                icon: Icon(Icons.skip_previous_rounded,
                    color: _audio.prevSong != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                    size: 36),
                onPressed: _audio.prevSong == null ? null : () {
                  final conn = context.read<ConnectionProvider>();
                  _audio.playPrev(conn);
                  setState(() => _currentSong = _audio.currentSong!);
                },
              ),
              GestureDetector(
                onTap: isLoading ? null : () => _audio.togglePlayPause(context.read<ConnectionProvider>()),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [AppTheme.primary, Color(0xFF9B59B6)]),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2),
                    ],
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next_rounded,
                    color: _audio.nextSong != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                    size: 36),
                onPressed: _audio.nextSong == null ? null : () {
                  final conn = context.read<ConnectionProvider>();
                  _audio.playNext(conn);
                  setState(() => _currentSong = _audio.currentSong!);
                },
              ),
              IconButton(
                icon: Icon(
                  _repeatMode == 2
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: _repeatMode > 0
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  size: 24,
                ),
                onPressed: () =>
                    setState(() => _repeatMode = (_repeatMode + 1) % 3),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
