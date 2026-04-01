import 'dart:convert';
import 'package:block_flutter/block_flutter.dart';

class Song {
  final String bid;
  final String title;
  final String? cid;
  final List<String> linkBids; // block data 里 link 字段，存的是关联集合的 BID

  const Song({
    required this.bid,
    required this.title,
    this.cid,
    this.linkBids = const [],
  });

  factory Song.fromBlock(BlockModel block) {
    final bid = block.maybeString('bid') ?? '';
    final name = block.maybeString('name') ?? block.maybeString('fileName') ?? '未知歌曲';
    final ipfs = block.getMap('ipfs');
    final cid = ipfs['cid'] as String?;

    // 读取 link 字段（关联集合 BID 列表）
    final rawLink = block.data['link'];
    final linkBids = rawLink is List
        ? rawLink.whereType<String>().where((s) => s.isNotEmpty).toList()
        : <String>[];

    return Song(bid: bid, title: name, cid: cid, linkBids: linkBids);
  }

  Map<String, dynamic> toJson() => {
    'bid': bid,
    'title': title,
    if (cid != null) 'cid': cid,
    'linkBids': linkBids,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    bid: json['bid'] as String? ?? '',
    title: json['title'] as String? ?? '未知歌曲',
    cid: json['cid'] as String?,
    linkBids: (json['linkBids'] as List?)?.whereType<String>().toList() ?? [],
  );

  String toJsonString() => jsonEncode(toJson());

  static Song? tryFromJsonString(String? s) {
    if (s == null) return null;
    try {
      return Song.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String get coverColor {
    const colors = ['6C63FF', 'FF6584', '43E97B', 'F7971E', 'A18CD1', '4FACFE', 'FA709A', '30CFD0'];
    final idx = bid.isNotEmpty ? bid.codeUnitAt(0) % colors.length : 0;
    return colors[idx];
  }
}
