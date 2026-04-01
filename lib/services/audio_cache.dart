import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AudioCache {
  AudioCache._();
  static final AudioCache instance = AudioCache._();

  Future<Directory> get _cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/audio_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _fileName(String cid) {
    // 去掉非法字符，保留 cid 作为文件名
    return cid.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }

  /// 检查本地是否已缓存
  Future<File?> getCached(String cid) async {
    final dir = await _cacheDir;
    final file = File('${dir.path}/${_fileName(cid)}');
    return await file.exists() ? file : null;
  }

  /// 下载并缓存，返回本地文件路径
  Future<String> downloadAndCache(String url, String cid) async {
    // 先检查缓存
    final cached = await getCached(cid);
    if (cached != null) return cached.path;

    final dir = await _cacheDir;
    final file = File('${dir.path}/${_fileName(cid)}');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('下载失败 HTTP ${response.statusCode}');
    }

    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  /// 删除单个缓存
  Future<void> remove(String cid) async {
    final cached = await getCached(cid);
    await cached?.delete();
  }

  /// 清空所有音频缓存
  Future<void> clearAll() async {
    final dir = await _cacheDir;
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 获取缓存总大小（字节）
  Future<int> totalSize() async {
    final dir = await _cacheDir;
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
