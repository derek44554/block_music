import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/collection_provider.dart';
import '../theme/app_theme.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool isPlaying;
  final VoidCallback? onMore;

  const SongCard({super.key, required this.song, this.onTap, this.isPlaying = false, this.onMore});

  @override
  Widget build(BuildContext context) {
    // 找到与用户集合匹配的名称
    final colProvider = context.read<CollectionProvider>();
    final names = colProvider.matchedCollectionNames(song.linkBids);
    final subtitle = names.isNotEmpty ? names.join(' · ') : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: isPlaying
              ? Border.all(color: AppTheme.primary.withValues(alpha: 0.6), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            _CoverArt(color: song.coverColor, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: isPlaying ? AppTheme.primary : AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isPlaying)
              const _PlayingIndicator()
            else
              GestureDetector(
                onTap: onMore,
                child: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  final String color;
  final double size;

  const _CoverArt({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = Color(int.parse('FF$color', radix: 16));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, c.withValues(alpha: 0.5)],
        ),
      ),
      child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.8), size: size * 0.45),
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator();

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final heights = [0.6, 1.0, 0.4];
          return Container(
            width: 3,
            height: 14 * (heights[i] + _ctrl.value * 0.4),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class CoverArtWidget extends StatelessWidget {
  final String color;
  final double size;

  const CoverArtWidget({super.key, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => _CoverArt(color: color, size: size);
}
