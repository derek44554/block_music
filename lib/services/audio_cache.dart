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

  String _safeName(String cid) {
    // 去掉非法字符，保留 cid 作为文件名
    return cid.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }

  String _extFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.mp3')) return '.mp3';
    if (path.endsWith('.m4a')) return '.m4a';
    if (path.endsWith('.aac')) return '.aac';
    if (path.endsWith('.wav')) return '.wav';
    if (path.endsWith('.flac')) return '.flac';
    if (path.endsWith('.ogg')) return '.ogg';
    return '';
  }

  String _extFromContentType(String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('audio/mpeg') || ct.contains('audio/mp3')) return '.mp3';
    if (ct.contains('audio/mp4') || ct.contains('audio/x-m4a')) return '.m4a';
    if (ct.contains('audio/aac')) return '.aac';
    if (ct.contains('audio/wav') || ct.contains('audio/x-wav')) return '.wav';
    if (ct.contains('audio/flac')) return '.flac';
    if (ct.contains('audio/ogg')) return '.ogg';
    return '';
  }

  Future<List<File>> _candidateFiles(Directory dir, String cid) async {
    final safe = _safeName(cid);
    return [
      File('${dir.path}/$safe.mp3'),
      File('${dir.path}/$safe.m4a'),
      File('${dir.path}/$safe.aac'),
      File('${dir.path}/$safe.wav'),
      File('${dir.path}/$safe.flac'),
      File('${dir.path}/$safe.ogg'),
      File('${dir.path}/$safe'),
    ];
  }

  /// 检查本地是否已缓存
  Future<File?> getCached(String cid) async {
    final dir = await _cacheDir;
    final files = await _candidateFiles(dir, cid);
    for (final file in files) {
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    }
    return null;
  }

  /// 下载并缓存，返回本地文件路径
  Future<String> downloadAndCache(String url, String cid) async {
    // 先检查缓存
    final cached = await getCached(cid);
    if (cached != null) return cached.path;

    final dir = await _cacheDir;
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('下载失败 HTTP ${response.statusCode}');
    }

    final byContentType = _extFromContentType(response.headers['content-type']);
    final byUrl = _extFromUrl(url);
    final ext = byContentType.isNotEmpty
        ? byContentType
        : (byUrl.isNotEmpty ? byUrl : '.mp3');

    final safe = _safeName(cid);
    final file = File('${dir.path}/$safe$ext');
    final temp = File('${dir.path}/$safe$ext.part');

    await temp.writeAsBytes(response.bodyBytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
    return file.path;
  }

  /// 删除单个缓存
  Future<void> remove(String cid) async {
    final dir = await _cacheDir;
    final files = await _candidateFiles(dir, cid);
    for (final file in files) {
      if (await file.exists()) {
        await file.delete();
      }
      final part = File('${file.path}.part');
      if (await part.exists()) {
        await part.delete();
      }
    }
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
