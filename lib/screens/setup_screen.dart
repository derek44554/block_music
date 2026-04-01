import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:block_flutter/block_flutter.dart';
import '../providers/connection_provider.dart';
import '../theme/app_theme.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: '我的节点');
  final _addressCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _ipfsCtrl = TextEditingController();
  bool _testing = false;
  bool _keyVisible = false;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _ipfsCtrl.text = context.read<ConnectionProvider>().ipfsEndpoint ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _keyCtrl.dispose();
    _ipfsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveIpfs() async {
    final ipfs = _ipfsCtrl.text.trim();
    await context.read<ConnectionProvider>().setIpfsEndpoint(ipfs.isEmpty ? null : ipfs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('IPFS 地址已保存'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _testAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _testing = true; _testError = null; });

    final connection = ConnectionModel(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
      keyBase64: _keyCtrl.text.trim(),
      status: ConnectionStatus.connecting,
    );

    try {
      final api = NodeApi(connection: connection);
      await api.getSignature();
      if (!mounted) return;
      await context.read<ConnectionProvider>().addConnection(
        connection.copyWith(status: ConnectionStatus.connected),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _testError = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('节点设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── IPFS 端点（独立 section，可单独保存）──
            _label('媒体服务'),
            _card(Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row(Icons.link_rounded, TextField(
                  controller: _ipfsCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'IPFS 端点',
                    hintText: 'http://192.168.1.100:8080',
                    border: InputBorder.none,
                    isDense: true,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                  keyboardType: TextInputType.url,
                )),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saveIpfs,
                    child: const Text('保存'),
                  ),
                ),
              ],
            )),

            const SizedBox(height: 20),

            // ── 已配置节点 ──
            if (provider.connections.isNotEmpty) ...[
              _label('已配置节点'),
              ...provider.connections.asMap().entries.map((e) => _NodeCard(
                    connection: e.value,
                    isActive: provider.activeConnection?.address == e.value.address,
                    onSwitch: provider.activeConnection?.address == e.value.address
                        ? null
                        : () => provider.setActive(e.key),
                    onDelete: () => _confirmDelete(context, e.key, e.value.name),
                  )),
              const SizedBox(height: 20),
            ],

            // ── 添加节点 ──
            _label('添加节点'),
            _card(Form(
              key: _formKey,
              child: Column(
                children: [
                  _row(Icons.label_outline_rounded, TextFormField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '节点名称', border: InputBorder.none, isDense: true,
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? '请输入名称' : null,
                  )),
                  _divider(),
                  _row(Icons.dns_rounded, TextFormField(
                    controller: _addressCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '节点地址', hintText: 'http://192.168.1.100:8080',
                      border: InputBorder.none, isDense: true,
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入地址';
                      if (!v.trim().startsWith('http')) return '地址需以 http:// 开头';
                      return null;
                    },
                  )),
                  _divider(),
                  _row(Icons.key_rounded, TextFormField(
                    controller: _keyCtrl,
                    obscureText: !_keyVisible,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'AES 密钥（Base64）',
                      border: InputBorder.none, isDense: true,
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _keyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 18, color: AppTheme.textSecondary,
                        ),
                        onPressed: () => setState(() => _keyVisible = !_keyVisible),
                      ),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? '请输入密钥' : null,
                  )),
                  if (_testError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_testError!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _testing ? null : _testAndSave,
                      icon: _testing
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(_testing ? '连接中...' : '测试并保存'),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.primary, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      );

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      );

  Widget _row(IconData icon, Widget child) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      );

  Widget _divider() => Divider(
      height: 20, indent: 30, color: Colors.white.withValues(alpha: 0.08));

  void _confirmDelete(BuildContext context, int index, String name) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除节点', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定要删除节点「$name」吗？',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              context.read<ConnectionProvider>().removeConnection(index);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ── 节点卡片 ──────────────────────────────────────────────────

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.connection,
    required this.isActive,
    required this.onDelete,
    this.onSwitch,
  });

  final ConnectionModel connection;
  final bool isActive;
  final VoidCallback? onSwitch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primary.withValues(alpha: 0.15)
            : AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primary : AppTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 18,
                color: isActive ? Colors.white : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(connection.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                            color: isActive
                                ? AppTheme.primary
                                : AppTheme.textPrimary,
                          )),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('当前',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(connection.address,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onSwitch != null)
              TextButton(
                onPressed: onSwitch,
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('切换'),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
