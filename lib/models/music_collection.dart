class MusicCollection {
  MusicCollection({
    required this.bid,
    required Map<String, dynamic> block,
    this.isDefault = false,
  }) : _block = Map.unmodifiable(Map<String, dynamic>.from(block));

  MusicCollection._internal({
    required this.bid,
    required Map<String, dynamic> block,
    required this.isDefault,
  }) : _block = Map.unmodifiable(block);

  final String bid;
  final Map<String, dynamic> _block;
  final bool isDefault;

  String? get title => (_block['name'] as String?)?.trim();
  Map<String, dynamic> get block => Map<String, dynamic>.from(_block);

  List<String> get linkTags {
    final raw = _block['link_tag'];
    if (raw is List) return raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return [];
  }

  MusicCollection copyWith({String? bid, Map<String, dynamic>? block, bool? isDefault}) {
    return MusicCollection._internal(
      bid: bid ?? this.bid,
      block: block != null ? Map<String, dynamic>.from(block) : Map<String, dynamic>.from(_block),
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {'bid': bid, 'block': _block, 'isDefault': isDefault};

  factory MusicCollection.fromJson(Map<String, dynamic> json) {
    final rawBlock = json['block'];
    final blockMap = rawBlock is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawBlock)
        : <String, dynamic>{};
    final resolvedBid = (json['bid'] as String?) ?? (blockMap['bid'] as String?) ?? '';
    return MusicCollection._internal(
      bid: resolvedBid,
      block: blockMap,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
