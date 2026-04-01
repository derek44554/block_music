import 'package:block_flutter/block_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/connection_provider.dart';
import '../models/song.dart';

class MusicService {
  MusicService(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  ConnectionModel get _connection {
    final c = _connectionProvider.activeConnection;
    if (c == null) throw StateError('No active connection available.');
    return c;
  }

  BlockApi get _api => BlockApi(connection: _connection);

  /// 获取集合 block 信息
  Future<Map<String, dynamic>> fetchCollectionBlock(String bid) async {
    return _api.getBlock(bid: bid);
  }

  /// 从 SharedPreferences 读取上次缓存的 BID 列表（立即返回，无网络）
  Future<List<String>> loadCachedBids(String collectionBid, {String? tag}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'music_bids_$collectionBid${tag != null ? '_$tag' : ''}';
    return prefs.getStringList(key) ?? [];
  }

  Future<void> _saveCachedBids(String collectionBid, List<String> bids, {String? tag}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'music_bids_$collectionBid${tag != null ? '_$tag' : ''}';
    await prefs.setStringList(key, bids);
  }

  /// 后台全量同步：拉取最新 BID 列表并写入缓存
  Future<List<String>> syncCollectionBids({
    required String collectionBid,
    String? tag,
    void Function(int fetched, int total)? onProgress,
  }) async {
    final result = <String>[];
    int page = 1;
    const limit = 100;
    while (true) {
      final response = await _api.getLinksByMain(
        bid: collectionBid,
        page: page,
        limit: limit,
        tag: tag,
        order: 'desc',
      );
      final data = response['data'];
      if (data is! Map<String, dynamic>) break;
      final items = data['items'];
      if (items is! List || items.isEmpty) break;
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final block = BlockModel(data: item);
        final bid = block.maybeString('bid');
        if (bid != null) {
          await BlockCache.instance.put(bid, block);
          result.add(bid);
        }
      }
      onProgress?.call(result.length, result.length);
      if (items.length < limit) break;
      page++;
    }
    await _saveCachedBids(collectionBid, result, tag: tag);
    return result;
  }

  /// 更新歌曲的 link 字段（关联集合 BID 列表）
  Future<void> updateSongLinks(Song song, List<String> newLinkBids) async {
    final cached = await BlockCache.instance.get(song.bid);
    if (cached == null) return;
    final data = Map<String, dynamic>.from(cached.data);
    data['link'] = newLinkBids;
    final updated = BlockModel(data: data);
    await BlockCache.instance.put(song.bid, updated);
    await _api.saveBlock(data: data);
  }
  /// 删除歌曲 block（网络 + 本地缓存）
  Future<void> deleteSong(String bid) async {
    await _api.deleteBlock(bid: bid);
    await BlockCache.instance.remove(bid);
  }

  Future<List<Song>> getLocalSongs({
    required List<String> bids,
    required int page,
    int limit = 40,
  }) async {
    final start = (page - 1) * limit;
    if (start >= bids.length) return [];
    final end = (start + limit).clamp(0, bids.length);
    final pageBids = bids.sublist(start, end);

    final result = <Song>[];
    for (final bid in pageBids) {
      final block = await BlockCache.instance.get(bid);
      if (block != null) result.add(Song.fromBlock(block));
    }
    return result;
  }
}
