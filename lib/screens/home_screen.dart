import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../models/song.dart';
import '../models/music_collection.dart';
import '../providers/connection_provider.dart';
import '../providers/collection_provider.dart';
import '../services/music_service.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_card.dart';
import 'app_settings_screen.dart';
import 'player_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final Song? initialSong;
  const HomeScreen({super.key, this.initialSong});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollCtrl = ScrollController();

  Song? _nowPlaying;
  int? _selectedIndex; // null = 全部
  String? _selectedTag;

  // 歌曲列表状态
  List<Song> _songs = [];
  List<String> _allBids = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _syncing = false;
  String? _error;

  double? _dragStartX;
  StreamSubscription<Song>? _songSub;

  @override
  void initState() {
    super.initState();
    _nowPlaying = widget.initialSong;
    _scrollCtrl.addListener(_onScroll);
    // 监听 AudioService 的歌曲切换，同步更新底部 mini player
    _songSub = AudioService.instance.currentSongStream.listen((song) {
      if (mounted) setState(() => _nowPlaying = song);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadSongs(reset: true),
    );
  }

  @override
  void dispose() {
    _songSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  ConnectionProvider get _connProvider => context.read<ConnectionProvider>();
  CollectionProvider get _colProvider => context.read<CollectionProvider>();

  MusicCollection? get _selectedCollection {
    if (_selectedIndex == null) return null;
    final cols = _colProvider.collections;
    if (_selectedIndex! >= cols.length) return null;
    return cols[_selectedIndex!];
  }

  Future<void> _loadSongs({bool reset = false}) async {
    if (!_connProvider.hasActiveConnection) return;
    final col = _selectedCollection;
    if (col == null && _colProvider.collections.isEmpty) {
      setState(() {
        _songs = [];
        _loading = false;
      });
      return;
    }

    if (_loading && !reset) return;
    if (!reset && !_hasMore) return;

    final service = MusicService(_connProvider);

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
      _page = 1;

      if (col != null) {
        // 1. 先读本地持久化 BID 列表（无网络，立即返回）
        final cachedBids = await service.loadCachedBids(
          col.bid,
          tag: _selectedTag,
        );
        if (cachedBids.isNotEmpty) {
          _allBids = cachedBids;
          final songs = await service.getLocalSongs(bids: _allBids, page: 1);
          if (mounted) {
            setState(() {
              _songs = songs;
              _page = 2;
              _hasMore = songs.length == 40;
              _loading = false;
            });
            _restoreQueueIfNeeded();
          }
        }
        // 2. 后台同步最新数据
        _syncInBackground(service, col.bid, tag: _selectedTag);
      } else {
        // 全部：只加载默认集合的缓存 BID
        final allBids = <String>[];
        for (final c in _colProvider.defaultCollections) {
          final bids = await service.loadCachedBids(c.bid);
          allBids.addAll(bids);
        }
        _allBids = allBids;
        if (_allBids.isNotEmpty) {
          final songs = await service.getLocalSongs(bids: _allBids, page: 1);
          if (mounted) {
            setState(() {
              _songs = songs;
              _page = 2;
              _hasMore = songs.length == 40;
              _loading = false;
            });
            _restoreQueueIfNeeded();
            // 首次加载完成后滚动到当前播放位置
            if (widget.initialSong != null) _scrollToCurrentSong();
          }
        }
        // 后台同步所有集合
        _syncAllInBackground(service);
      }
      return;
    }

    // 翻页：直接从本地缓存读
    try {
      final songs = await service.getLocalSongs(bids: _allBids, page: _page);
      if (mounted) {
        setState(() {
          _songs.addAll(songs);
          _page++;
          _hasMore = songs.length == 40;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _syncInBackground(
    MusicService service,
    String collectionBid, {
    String? tag,
  }) async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final bids = await service.syncCollectionBids(
        collectionBid: collectionBid,
        tag: tag,
      );
      _allBids = bids;
      final songs = await service.getLocalSongs(bids: bids, page: 1);
      if (mounted) {
        setState(() {
          _songs = songs;
          _page = 2;
          _hasMore = songs.length == 40;
        });
      }
    } catch (_) {
      // 后台同步失败不影响已展示内容
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    await _loadSongs();
  }

  Future<void> _syncAllInBackground(MusicService service) async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final allBids = <String>[];
      for (final c in _colProvider.defaultCollections) {
        final bids = await service.syncCollectionBids(collectionBid: c.bid);
        allBids.addAll(bids);
      }
      _allBids = allBids;
      final songs = await service.getLocalSongs(bids: _allBids, page: 1);
      if (mounted) {
        setState(() {
          _songs = songs;
          _page = 2;
          _hasMore = songs.length == 40;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _loading = false;
        });
      }
    }
  }

  void _scrollToCurrentSong() {
    final song = _nowPlaying;
    if (song == null || _songs.isEmpty) return;
    final idx = _songs.indexWhere((s) => s.bid == song.bid);
    if (idx < 0) return;
    // 每个 SongCard 大约 76px 高（padding 12*2 + content 52）
    const itemHeight = 76.0;
    final offset = (idx * itemHeight - 200).clamp(0.0, double.infinity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          offset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _restoreQueueIfNeeded() {
    if (_songs.isEmpty) return;
    final current = AudioService.instance.currentSong;
    if (current == null) return;
    final idx = _songs.indexWhere((s) => s.bid == current.bid);
    if (idx >= 0) AudioService.instance.setQueue(_songs, idx);
  }

  void _selectCollection(int? index) {
    setState(() {
      _selectedIndex = index;
      _selectedTag = null;
      _songs = [];
      _allBids = [];
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    _scaffoldKey.currentState?.closeEndDrawer();
    _loadSongs(reset: true);
  }

  void _selectTag(String? tag) {
    setState(() {
      _selectedTag = tag;
      _songs = [];
      _allBids = [];
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    _scaffoldKey.currentState?.closeEndDrawer();
    _loadSongs(reset: true);
  }

  void _play(Song song) {
    setState(() => _nowPlaying = song);
    final conn = context.read<ConnectionProvider>();
    AudioService.instance.setQueue(
      _songs,
      _songs.indexWhere((s) => s.bid == song.bid),
    );
    if (AudioService.instance.currentSong?.bid != song.bid ||
        AudioService.instance.player.processingState == ProcessingState.idle) {
      AudioService.instance.play(song, conn);
    }
  }

  void _openPlayer(Song song) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PlayerScreen(song: song),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  String get _currentTitle {
    final col = _selectedCollection;
    if (col != null) return col.title ?? col.bid.substring(0, 8);
    return 'BlockMusic';
  }

  @override
  Widget build(BuildContext context) {
    final connProvider = context.watch<ConnectionProvider>();
    final colProvider = context.watch<CollectionProvider>();
    final hasCollections = colProvider.collections.isNotEmpty;
    final isMacOS = !kIsWeb && Platform.isMacOS;

    return Scaffold(
      key: _scaffoldKey,
      endDrawerEnableOpenDragGesture: !isMacOS,
      drawerEnableOpenDragGesture: false,
      appBar: isMacOS ? null : _buildAppBar(connProvider, hasCollections),
      endDrawer: isMacOS
          ? null
          : _MusicDrawer(
              collections: colProvider.collections,
              selectedIndex: _selectedIndex,
              selectedTag: _selectedTag,
              onSelect: _selectCollection,
              onSelectTag: _selectTag,
              onAdd: () {
                _scaffoldKey.currentState?.closeEndDrawer();
                _showAddCollectionDialog(context);
              },
              onDelete: (bid) {
                colProvider.removeCollection(bid);
                if (_selectedIndex != null) _selectCollection(null);
              },
              onToggleDefault: (bid, val) {
                colProvider.toggleDefault(bid, val);
                if (_selectedIndex == null) _loadSongs(reset: true);
              },
              onSettings: () {
                _scaffoldKey.currentState?.closeEndDrawer();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
                );
              },
            ),
      body: isMacOS
          ? _buildMacDesktopLayout(connProvider, colProvider, hasCollections)
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (d) => _dragStartX = d.globalPosition.dx,
              onHorizontalDragUpdate: (d) {
                if (_dragStartX == null) return;
                if (_dragStartX! - d.globalPosition.dx > 20) {
                  _scaffoldKey.currentState?.openEndDrawer();
                  _dragStartX = null;
                }
              },
              onHorizontalDragEnd: (_) => _dragStartX = null,
              child: !connProvider.hasActiveConnection
                  ? _buildNoConnection()
                  : _buildBody(hasCollections),
            ),
      bottomNavigationBar: !isMacOS && _nowPlaying != null
          ? MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: _MiniPlayerBar(
                song: _nowPlaying!,
                onTap: () => _openPlayer(_nowPlaying!),
              ),
            )
          : null,
    );
  }

  Widget _buildMacDesktopLayout(
    ConnectionProvider connProvider,
    CollectionProvider colProvider,
    bool hasCollections,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1160;
        final menuWidth = isCompact ? 280.0 : 308.0;
        final gap = isCompact ? 10.0 : 14.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: menuWidth,
                child: _MusicDrawer(
                  embedded: true,
                  brandTitle: _currentTitle,
                  collections: colProvider.collections,
                  selectedIndex: _selectedIndex,
                  selectedTag: _selectedTag,
                  onSelect: _selectCollection,
                  onSelectTag: _selectTag,
                  onAdd: () => _showAddCollectionDialog(context),
                  onDelete: (bid) {
                    colProvider.removeCollection(bid);
                    if (_selectedIndex != null) _selectCollection(null);
                  },
                  onToggleDefault: (bid, val) {
                    colProvider.toggleDefault(bid, val);
                    if (_selectedIndex == null) _loadSongs(reset: true);
                  },
                  onSettings: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AppSettingsScreen(),
                    ),
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withValues(alpha: 0.03),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: !connProvider.hasActiveConnection
                              ? _buildNoConnection()
                              : _buildBody(
                                  hasCollections,
                                  bottomSpacing: _nowPlaying != null
                                      ? 168
                                      : 100,
                                ),
                        ),
                        if (_nowPlaying != null)
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: _MiniPlayerBar(
                              song: _nowPlaying!,
                              onTap: () => _openPlayer(_nowPlaying!),
                              isMacEmbedded: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(ConnectionProvider connProvider, bool hasCollections) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF9B59B6)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _currentTitle,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          if (_syncing) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (hasCollections)
          IconButton(
            icon: Badge(
              isLabelVisible: _selectedIndex != null,
              child: const Icon(Icons.queue_music_rounded),
            ),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          )
        else
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddCollectionDialog(context),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildNoConnection() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.card,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '尚未配置节点',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '添加一个 Block 节点来开始播放你的音乐',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SetupScreen()),
            ).then((_) => setState(() {})),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加节点'),
          ),
        ],
      ),
    ),
  );

  Widget _buildBody(bool hasCollections, {double bottomSpacing = 100}) {
    if (!hasCollections) return _buildEmptyCollections();

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (_selectedIndex != null)
          SliverToBoxAdapter(child: _buildCollectionHeader()),
        if (_songs.isEmpty && _loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_songs.isEmpty && _error != null)
          SliverFillRemaining(child: _buildError())
        else if (_songs.isEmpty)
          SliverFillRemaining(child: _buildEmpty())
        else ...[
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => SongCard(
                song: _songs[i],
                isPlaying: _nowPlaying?.bid == _songs[i].bid,
                onTap: () => _play(_songs[i]),
                onMore: () => _showSongOptions(context, _songs[i]),
              ),
              childCount: _songs.length,
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: bottomSpacing)),
      ],
    );
  }

  Widget _buildCollectionHeader() {
    final col = _selectedCollection!;
    const colors = ['6C63FF', 'FF6584', '43E97B', 'F7971E', 'A18CD1', '4FACFE'];
    final colorHex = colors[(_selectedIndex ?? 0) % colors.length];
    final c = Color(int.parse('FF$colorHex', radix: 16));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.5), AppTheme.card],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.4)]),
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                col.title ?? col.bid.substring(0, 8),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${_songs.length} 首歌',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCollections() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.card,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.library_music_outlined,
              size: 40,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有歌单',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击添加一个集合 BID 来开始播放',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _showAddCollectionDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加集合'),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty() => const Center(
    child: Padding(
      padding: EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_off_rounded,
            size: 48,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 16),
          Text(
            '该集合暂无歌曲',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
          ),
        ],
      ),
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? '加载失败',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _loadSongs(reset: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );

  void _showAddCollectionDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '添加集合',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: '输入集合 BID',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final bid = ctrl.text.trim();
              if (bid.isEmpty) return;
              Navigator.pop(context);
              await _addCollection(bid);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppTheme.primary,
                ),
                title: const Text(
                  '选择集合',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showCollectionPicker(context, song);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  '删除',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteSong(song);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCollectionPicker(BuildContext context, Song song) {
    final collections = _colProvider.collections;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        var linked = Set<String>.from(song.linkBids);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void toggle(String bid) {
              setSheet(() {
                if (linked.contains(bid)) {
                  linked = Set.from(linked)..remove(bid);
                } else {
                  linked = Set.from(linked)..add(bid);
                }
              });
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '选择集合',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView(
                      shrinkWrap: true,
                      children: collections.isEmpty
                          ? [
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  '没有可用的集合',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ]
                          : collections.map((col) {
                              final isLinked = linked.contains(col.bid);
                              final c = _collectionColor(
                                collections.indexOf(col),
                              );
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                leading: Icon(
                                  Icons.queue_music_rounded,
                                  color: isLinked ? AppTheme.primary : c,
                                ),
                                title: Text(
                                  col.title ??
                                      col.bid.substring(
                                        0,
                                        col.bid.length.clamp(0, 10),
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isLinked
                                        ? AppTheme.primary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                trailing: Icon(
                                  isLinked
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: isLinked
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                ),
                                onTap: () => toggle(col.bid),
                              );
                            }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _saveLinks(song, linked.toList());
                        },
                        child: const Text('保存'),
                      ),
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

  Color _collectionColor(int i) {
    const colors = ['6C63FF', 'FF6584', '43E97B', 'F7971E', 'A18CD1', '4FACFE'];
    return Color(int.parse('FF${colors[i % colors.length]}', radix: 16));
  }

  Future<void> _saveLinks(Song song, List<String> newLinkBids) async {
    if (!_connProvider.hasActiveConnection) return;
    try {
      final service = MusicService(_connProvider);
      await service.updateSongLinks(song, newLinkBids);
      // 刷新本地列表
      setState(() {
        final idx = _songs.indexWhere((s) => s.bid == song.bid);
        if (idx >= 0) {
          _songs[idx] = Song(
            bid: song.bid,
            title: song.title,
            cid: song.cid,
            linkBids: newLinkBids,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteSong(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '删除歌曲',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要删除「${song.title}」吗？此操作不可撤销。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final service = MusicService(_connProvider);
      await service.deleteSong(song.bid);
      setState(() {
        _songs.removeWhere((s) => s.bid == song.bid);
        _allBids.remove(song.bid);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _addCollection(String bid) async {
    if (!_connProvider.hasActiveConnection) return;
    try {
      final service = MusicService(_connProvider);
      final response = await service.fetchCollectionBlock(bid);
      final data = response['data'];
      final blockData = data is Map<String, dynamic> ? data : response;
      final collection = MusicCollection(bid: bid, block: blockData);
      await _colProvider.addCollection(collection);
      // 自动切换到新集合
      final newIndex = _colProvider.collections.indexWhere((c) => c.bid == bid);
      if (newIndex >= 0) _selectCollection(newIndex);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败：$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}

// ── 右侧歌单抽屉 ──────────────────────────────────────────────

class _MusicDrawer extends StatefulWidget {
  final bool embedded;
  final String? brandTitle;
  final List<MusicCollection> collections;
  final int? selectedIndex;
  final String? selectedTag;
  final void Function(int? index) onSelect;
  final void Function(String? tag) onSelectTag;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final void Function(String bid) onDelete;
  final void Function(String bid, bool isDefault) onToggleDefault;

  const _MusicDrawer({
    this.embedded = false,
    this.brandTitle,
    required this.collections,
    required this.selectedIndex,
    required this.selectedTag,
    required this.onSelect,
    required this.onSelectTag,
    required this.onAdd,
    required this.onSettings,
    required this.onDelete,
    required this.onToggleDefault,
  });

  @override
  State<_MusicDrawer> createState() => _MusicDrawerState();
}

class _MusicDrawerState extends State<_MusicDrawer> {
  final Map<String, bool> _expanded = {};

  bool _isExpanded(MusicCollection col) {
    return _expanded[col.bid] ??
        (widget.selectedIndex != null &&
            widget.collections.indexOf(col) == widget.selectedIndex);
  }

  void _toggleExpanded(MusicCollection col) {
    setState(() => _expanded[col.bid] = !_isExpanded(col));
  }

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      decoration: widget.embedded
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            )
          : null,
      child: SafeArea(
        top: !widget.embedded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.embedded)
              const DragToMoveArea(
                child: SizedBox(height: 18, width: double.infinity),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, widget.embedded ? 8 : 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: widget.embedded ? 30 : 20,
                    height: widget.embedded ? 30 : 20,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, Color(0xFF9B59B6)],
                      ),
                      borderRadius: BorderRadius.circular(
                        widget.embedded ? 9 : 6,
                      ),
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: widget.embedded ? 16 : 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.embedded
                              ? (widget.brandTitle ?? '纯音乐')
                              : '我的集合',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: widget.embedded ? 17 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.embedded)
                          Text(
                            '我的集合',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.9,
                              ),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 4),
            _DrawerTile(
              icon: Icons.library_music_rounded,
              label: '全部',
              selected:
                  widget.selectedIndex == null && widget.selectedTag == null,
              onTap: () => widget.onSelect(null),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Text(
                    '集合列表',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    color: AppTheme.textSecondary,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                    tooltip: '添加集合',
                  ),
                ],
              ),
            ),
            if (widget.collections.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: widget.collections.length,
                  itemBuilder: (_, i) {
                    const normalCollectionColor = Color(0xFF8EA2C8);
                    const defaultCollectionColor = Color(0xFFF6C85E);
                    final col = widget.collections[i];
                    final tags = col.linkTags;
                    final hasTags = tags.isNotEmpty;
                    final expanded = _isExpanded(col);
                    final isSelected = widget.selectedIndex == i;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DrawerTile(
                          icon: Icons.queue_music_rounded,
                          iconColor: col.isDefault
                              ? defaultCollectionColor
                              : normalCollectionColor,
                          label: col.title ?? col.bid.substring(0, 10),
                          subtitle: col.bid.length > 14
                              ? '${col.bid.substring(0, 6)}…${col.bid.substring(col.bid.length - 4)}'
                              : col.bid,
                          selected: isSelected && widget.selectedTag == null,
                          onTap: () => widget.onSelect(i),
                          onLongPress: () => _showDeleteSheet(context, col),
                          trailing: hasTags
                              ? GestureDetector(
                                  onTap: () => _toggleExpanded(col),
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      expanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: isSelected
                                          ? AppTheme.primary
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        if (hasTags && expanded)
                          ...tags.map(
                            (tag) => _TagTile(
                              tag: tag,
                              selected:
                                  widget.selectedIndex == i &&
                                  widget.selectedTag == tag,
                              onTap: () {
                                widget.onSelect(i);
                                widget.onSelectTag(tag);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ] else
              const Expanded(child: SizedBox()),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            _DrawerTile(
              icon: Icons.settings_rounded,
              label: '设置',
              selected: false,
              onTap: widget.onSettings,
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return panel;
    }

    return Drawer(width: 280, backgroundColor: AppTheme.surface, child: panel);
  }

  void _showDeleteSheet(BuildContext context, MusicCollection col) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  col.isDefault
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: col.isDefault ? Colors.amber : AppTheme.textSecondary,
                ),
                title: Text(
                  col.isDefault ? '取消默认显示' : '加入默认显示',
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleDefault(col.bid, !col.isDefault);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  '删除「${col.title ?? col.bid.substring(0, 8)}」',
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete(col.bid);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.close_rounded,
                  color: AppTheme.textSecondary,
                ),
                title: const Text(
                  '取消',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 抽屉列表项 ────────────────────────────────────────────────

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const _DrawerTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? AppTheme.primary
                      : (iconColor ?? AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (selected)
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tag 子列表项 ──────────────────────────────────────────────

class _TagTile extends StatelessWidget {
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const _TagTile({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, right: 8, top: 1, bottom: 1),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.label_outline_rounded,
                  size: 15,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini 播放条 ───────────────────────────────────────────────

class _MiniPlayerBar extends StatefulWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isMacEmbedded;
  const _MiniPlayerBar({
    required this.song,
    required this.onTap,
    this.isMacEmbedded = false,
  });

  @override
  State<_MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<_MiniPlayerBar> {
  bool _seeking = false;
  double _seekValue = 0;

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = Color(int.parse('FF${widget.song.coverColor}', radix: 16));
    final bottomPad = widget.isMacEmbedded
        ? 0.0
        : MediaQuery.of(context).padding.bottom;
    return StreamBuilder<PlayerState>(
      stream: AudioService.instance.playerStateStream,
      builder: (_, snap) {
        final isPlaying = snap.data?.playing ?? false;
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            decoration: widget.isMacEmbedded
                ? BoxDecoration(
                    color: const Color(0xFF10131C).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  )
                : const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                    ),
                  ),
            child: StreamBuilder<Duration?>(
              stream: AudioService.instance.durationStream,
              builder: (_, durSnap) {
                final total = durSnap.data ?? Duration.zero;
                return StreamBuilder<Duration?>(
                  stream: AudioService.instance.positionStream,
                  builder: (_, posSnap) {
                    final position = posSnap.data ?? Duration.zero;
                    final progress = total.inMilliseconds > 0
                        ? (position.inMilliseconds / total.inMilliseconds)
                              .clamp(0.0, 1.0)
                        : 0.0;
                    final displayProgress = _seeking ? _seekValue : progress;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            widget.isMacEmbedded ? 16 : 0,
                            widget.isMacEmbedded ? 8 : 0,
                            widget.isMacEmbedded ? 16 : 0,
                            0,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final trackWidth = constraints.maxWidth;
                              double toRatio(double dx) =>
                                  (dx / trackWidth).clamp(0.0, 1.0);
                              final thumbLeft =
                                  (displayProgress * trackWidth - 5).clamp(
                                    0.0,
                                    (trackWidth - 10).clamp(
                                      0.0,
                                      double.infinity,
                                    ),
                                  );

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart: (_) =>
                                    setState(() => _seeking = true),
                                onHorizontalDragUpdate: (d) {
                                  setState(
                                    () => _seekValue = toRatio(
                                      d.localPosition.dx,
                                    ),
                                  );
                                },
                                onHorizontalDragEnd: (_) {
                                  setState(() => _seeking = false);
                                  AudioService.instance.seek(
                                    Duration(
                                      milliseconds:
                                          (_seekValue * total.inMilliseconds)
                                              .round(),
                                    ),
                                  );
                                },
                                onTapDown: (d) {
                                  final ratio = toRatio(d.localPosition.dx);
                                  AudioService.instance.seek(
                                    Duration(
                                      milliseconds:
                                          (ratio * total.inMilliseconds)
                                              .round(),
                                    ),
                                  );
                                },
                                child: SizedBox(
                                  height: 18,
                                  child: Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      Container(
                                        height: 3,
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: displayProgress,
                                        child: Container(
                                          height: 3,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Positioned(
                                        left: thumbLeft,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // 控制按钮行
                        Padding(
                          padding: widget.isMacEmbedded
                              ? const EdgeInsets.fromLTRB(14, 4, 8, 10)
                              : EdgeInsets.fromLTRB(16, 0, 6, 8 + bottomPad),
                          child: Row(
                            children: [
                              // 封面
                              Container(
                                width: widget.isMacEmbedded ? 36 : 40,
                                height: widget.isMacEmbedded ? 36 : 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [c, c.withValues(alpha: 0.5)],
                                  ),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              // 标题
                              Expanded(
                                child: Text(
                                  widget.song.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 时间 0:20/4:23
                              Text(
                                '${_fmt(_seeking ? Duration(milliseconds: (_seekValue * total.inMilliseconds).round()) : position)}/${_fmt(total)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                              // 播放/暂停
                              IconButton(
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () =>
                                    AudioService.instance.togglePlayPause(
                                      context.read<ConnectionProvider>(),
                                    ),
                              ),
                              // 下一首
                              IconButton(
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  color: AudioService.instance.nextSong != null
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 28,
                                ),
                                onPressed:
                                    AudioService.instance.nextSong == null
                                    ? null
                                    : () => AudioService.instance.playNext(
                                        context.read<ConnectionProvider>(),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
