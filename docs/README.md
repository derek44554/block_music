# BlockMusic

基于 Block 去中心化网络的本地音乐播放器。

## 功能

- 通过 Block 节点连接，读取加密网络上的音乐集合
- 支持多集合管理，左滑打开集合抽屉
- 集合支持 link_tag 标签过滤
- 音频本地缓存，播放过的歌曲下次离线可用
- 记录上次播放状态，重启 App 后自动恢复
- 播放队列支持上一首 / 下一首切换
- 歌曲支持添加到多个集合、删除

## 架构

```
lib/
├── main.dart                  # 入口，初始化 Provider
├── models/
│   ├── song.dart              # 歌曲模型，支持序列化
│   └── music_collection.dart  # 集合模型，含 linkTags / isDefault
├── providers/
│   ├── connection_provider.dart  # 节点连接管理
│   └── collection_provider.dart  # 集合列表管理，持久化
├── services/
│   ├── music_service.dart     # Block 网络请求 + BID 缓存
│   ├── audio_service.dart     # 播放控制，队列管理
│   └── audio_cache.dart       # 音频文件本地磁盘缓存
├── screens/
│   ├── home_screen.dart       # 首页 + 抽屉 + Mini 播放条
│   ├── player_screen.dart     # 播放详情页
│   └── setup_screen.dart      # 节点 / IPFS 端点设置
├── widgets/
│   └── song_card.dart         # 歌曲列表项
└── theme/
    └── app_theme.dart         # 深色主题配置
```

## 配置

### 节点设置

打开 App → 右滑抽屉 → 节点设置，填写：

| 字段 | 说明 |
|------|------|
| 节点地址 | Block 节点 HTTP 地址，如 `http://192.168.1.100:8080` |
| AES 密钥 | Base64 编码的节点密钥 |
| IPFS 端点 | 音频 / 图片文件访问地址，如 `http://192.168.1.100:8080` |

### Android 签名

复制 `android/key.properties.example` 为 `android/key.properties`，填入签名信息：

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=/path/to/your.jks
```

## 构建

```bash
# 安装依赖
flutter pub get

# 调试运行
flutter run

# 发布 APK
flutter build apk --release

# 发布 AAB（Google Play）
flutter build appbundle --release
```

## 数据缓存

| 类型 | 位置 | 说明 |
|------|------|------|
| BID 列表 | SharedPreferences | 每个集合的歌曲 BID，key: `music_bids_{collectionBid}` |
| Block 数据 | BlockCache（SQLite） | 歌曲元数据 |
| 音频文件 | `Documents/audio_cache/` | 按 CID 命名的音频文件 |
| 上次播放 | SharedPreferences | key: `last_played_song` |

## 依赖

- [block_flutter](https://github.com/derek44554/block_flutter) — Block 网络 SDK
- [just_audio](https://pub.dev/packages/just_audio) — 音频播放
- [provider](https://pub.dev/packages/provider) — 状态管理
- [shared_preferences](https://pub.dev/packages/shared_preferences) — 本地持久化

## License

MIT License with Attribution Requirement — 详见 [LICENSE](../LICENSE)
