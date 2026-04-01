import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../providers/connection_provider.dart';
import 'audio_cache.dart';

const _lastSongKey = 'last_played_song';

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioPlayer _player = AudioPlayer();
  final _currentSongController = StreamController<Song>.broadcast();

  AudioPlayer get player => _player;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Song> get currentSongStream => _currentSongController.stream;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  List<Song> _queue = [];
  int _queueIndex = -1;

  void setQueue(List<Song> songs, int index) {
    _queue = songs;
    _queueIndex = index;
  }

  Song? get nextSong => _queueIndex < _queue.length - 1 ? _queue[_queueIndex + 1] : null;
  Song? get prevSong => _queueIndex > 0 ? _queue[_queueIndex - 1] : null;

  /// 启动时恢复上次播放的歌曲元数据（不自动播放）
  Future<Song?> restoreLastSong() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_lastSongKey);
    final song = Song.tryFromJsonString(json);
    if (song != null) _currentSong = song;
    return song;
  }

  Future<void> _persist(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSongKey, song.toJsonString());
  }

  String _buildUrl(Song song, ConnectionProvider connProvider) {
    final cid = song.cid ?? '';
    final endpoint = connProvider.ipfsEndpoint;
    if (endpoint != null && endpoint.isNotEmpty) {
      return '${endpoint.replaceAll(RegExp(r'/+$'), '')}/$cid';
    }
    final address = connProvider.activeConnection?.address ?? '';
    return '${address.replaceAll(RegExp(r'/+$'), '')}/ipfs/$cid';
  }

  Future<void> play(Song song, ConnectionProvider connProvider) async {
    final cid = song.cid;
    if (cid == null || cid.isEmpty) return;

    // 更新队列索引
    final idx = _queue.indexWhere((s) => s.bid == song.bid);
    if (idx >= 0) _queueIndex = idx;

    _currentSong = song;
    await _persist(song);
    _currentSongController.add(song);

    try {
      await _player.stop();

      final cached = await AudioCache.instance.getCached(cid);
      if (cached != null) {
        await _player.setFilePath(cached.path);
      } else {
        final url = _buildUrl(song, connProvider);
        await _player.setUrl(url);
        _cacheInBackground(url, cid);
      }
      await _player.play();
    } catch (e) {
      // 忽略 Connection aborted 等因快速切换导致的错误
      debugPrint('AudioService.play error: $e');
    }
  }

  void _cacheInBackground(String url, String cid) {
    AudioCache.instance.downloadAndCache(url, cid).catchError((e) => '');
  }

  Future<void> playNext(ConnectionProvider connProvider) async {
    final song = nextSong;
    if (song != null) await play(song, connProvider);
  }

  Future<void> playPrev(ConnectionProvider connProvider) async {
    final song = prevSong;
    if (song != null) await play(song, connProvider);
  }

  Future<void> togglePlayPause(ConnectionProvider? connProvider) async {
    // player 空闲（app 重启后）且有上次播放记录，重新加载
    if (_player.processingState == ProcessingState.idle) {
      final song = _currentSong;
      if (song != null && connProvider != null) {
        await play(song, connProvider);
      }
      return;
    }
    _player.playing ? await _player.pause() : await _player.play();
  }

  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> stop() => _player.stop();
  void dispose() => _player.dispose();
}
