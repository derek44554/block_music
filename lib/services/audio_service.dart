import 'dart:async';
import 'dart:io';
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

  Song? get nextSong =>
      _queueIndex < _queue.length - 1 ? _queue[_queueIndex + 1] : null;
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

  List<String> _buildCandidateUrls(Song song, ConnectionProvider connProvider) {
    final cid = (song.cid ?? '').trim();
    if (cid.isEmpty) return const [];

    final urls = <String>[];

    void addUrl(String? raw) {
      final value = (raw ?? '').trim();
      if (value.isEmpty || urls.contains(value)) return;
      urls.add(value);
    }

    final endpoint = connProvider.ipfsEndpoint;
    if (endpoint != null && endpoint.isNotEmpty) {
      final base = endpoint.replaceAll(RegExp(r'/+$'), '');
      if (base.endsWith('/ipfs')) {
        addUrl('$base/$cid');
      } else {
        addUrl('$base/ipfs/$cid');
      }
      // 一旦显式配置了 IPFS 端点，只使用该端点，避免误回退到节点地址。
      return urls;
    }

    final address = connProvider.activeConnection?.address ?? '';
    final normalizedAddress = address.replaceAll(RegExp(r'/+$'), '');
    if (normalizedAddress.isNotEmpty) {
      addUrl('$normalizedAddress/ipfs/$cid');
    }

    return urls;
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
      var loaded = false;
      if (cached != null) {
        try {
          await _player.setFilePath(cached.path);
          loaded = true;
        } catch (e) {
          debugPrint('AudioService.cached file invalid: ${cached.path} -> $e');
          await AudioCache.instance.remove(cid);
        }
      }

      if (!loaded) {
        final urls = _buildCandidateUrls(song, connProvider);
        if (urls.isEmpty) {
          throw Exception('未生成可用音频 URL');
        }

        String? selectedUrl;
        final preferLocalFirst = !kIsWeb && Platform.isMacOS;

        if (!preferLocalFirst) {
          for (final url in urls) {
            try {
              await _player.setUrl(url);
              selectedUrl = url;
              break;
            } catch (e) {
              debugPrint('AudioService.setUrl failed: $url -> $e');
            }
          }
        }

        if (selectedUrl == null) {
          // macOS 或流式失败时，回退到先下载再本地播放
          for (final url in urls) {
            try {
              final localPath = await AudioCache.instance.downloadAndCache(
                url,
                cid,
              );
              try {
                await _player.setFilePath(localPath);
              } catch (e) {
                debugPrint(
                  'AudioService.setFilePath from fallback failed: $localPath -> $e',
                );
                rethrow;
              }
              selectedUrl = url;
              break;
            } catch (e) {
              debugPrint('AudioService.download fallback failed: $url -> $e');
            }
          }
        } else {
          _cacheInBackground(selectedUrl, cid);
        }

        if (selectedUrl == null) {
          throw Exception('音频地址不可用，候选: ${urls.join(' | ')}');
        }
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
