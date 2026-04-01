import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_collection.dart';

const _collectionsKey = 'music_collections';

class CollectionProvider extends ChangeNotifier {
  List<MusicCollection> _collections = [];

  List<MusicCollection> get collections => List.unmodifiable(_collections);

  /// 默认显示的集合（用于"全部"视图）
  List<MusicCollection> get defaultCollections {
    final defaults = _collections.where((c) => c.isDefault).toList();
    return defaults.isNotEmpty ? defaults : _collections;
  }

  /// 根据歌曲的 linkBids，找到与用户集合匹配的名称（可能多个）
  List<String> matchedCollectionNames(List<String> linkBids) {
    if (linkBids.isEmpty || _collections.isEmpty) return [];
    final collectionBidSet = {for (final c in _collections) c.bid};
    return linkBids
        .where((bid) => collectionBidSet.contains(bid))
        .map((bid) => _collections.firstWhere((c) => c.bid == bid).title)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_collectionsKey) ?? [];
    try {
      _collections = raw
          .map((e) => MusicCollection.fromJson(jsonDecode(e) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _collections = [];
    }
    notifyListeners();
  }

  Future<void> addCollection(MusicCollection collection) async {
    final idx = _collections.indexWhere((c) => c.bid == collection.bid);
    if (idx >= 0) {
      final updated = [..._collections];
      updated[idx] = collection;
      _collections = updated;
    } else {
      _collections = [..._collections, collection];
    }
    await _persist();
    notifyListeners();
  }

  Future<void> toggleDefault(String bid, bool isDefault) async {
    _collections = _collections
        .map((c) => c.bid == bid ? c.copyWith(isDefault: isDefault) : c)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> removeCollection(String bid) async {    _collections = _collections.where((c) => c.bid != bid).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _collectionsKey,
      _collections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
