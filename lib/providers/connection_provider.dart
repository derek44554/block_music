import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_flutter/block_flutter.dart';

class ConnectionProvider extends ChangeNotifier {
  static const _storageKey = 'block_connections';
  static const _activeKey = 'block_active_index';

  List<ConnectionModel> _connections = [];
  ConnectionModel? _activeConnection;
  String? _ipfsEndpoint;

  List<ConnectionModel> get connections => List.unmodifiable(_connections);
  ConnectionModel? get activeConnection => _activeConnection;
  bool get hasActiveConnection => _activeConnection != null;
  String? get ipfsEndpoint => _ipfsEndpoint;

  static const _ipfsKey = 'block_ipfs_endpoint';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    _connections = raw
        .map(
          (e) =>
              ConnectionModel.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    if (_connections.isNotEmpty) {
      _activeConnection =
          _connections[activeIndex.clamp(0, _connections.length - 1)];
    }
    _ipfsEndpoint = prefs.getString(_ipfsKey);
    notifyListeners();
  }

  Future<void> addConnection(ConnectionModel connection) async {
    _connections.add(connection);
    if (_connections.length == 1) {
      _activeConnection = connection;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_activeKey, 0);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeConnection(int index) async {
    _connections.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    if (activeIndex >= _connections.length) {
      _activeConnection = _connections.isNotEmpty ? _connections[0] : null;
      await prefs.setInt(_activeKey, 0);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(int index) async {
    if (index < 0 || index >= _connections.length) return;
    _activeConnection = _connections[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeKey, index);
    notifyListeners();
  }

  Future<void> setIpfsEndpoint(String? endpoint) async {
    final raw = endpoint?.trim();
    if (raw == null || raw.isEmpty) {
      _ipfsEndpoint = null;
    } else {
      // 统一去掉末尾斜杠，后续拼接由 AudioService 统一处理。
      _ipfsEndpoint = raw.replaceAll(RegExp(r'/+$'), '');
    }
    final prefs = await SharedPreferences.getInstance();
    if (_ipfsEndpoint != null) {
      await prefs.setString(_ipfsKey, _ipfsEndpoint!);
    } else {
      await prefs.remove(_ipfsKey);
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _connections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
