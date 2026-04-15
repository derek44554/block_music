import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'models/song.dart';
import 'providers/connection_provider.dart';
import 'providers/collection_provider.dart';
import 'services/audio_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1120, 760),
      minimumSize: Size(900, 620),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final connProvider = ConnectionProvider();
  final colProvider = CollectionProvider();
  await Future.wait([connProvider.load(), colProvider.load()]);

  // 恢复上次播放的歌曲
  final lastSong = await AudioService.instance.restoreLastSong();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connProvider),
        ChangeNotifierProvider.value(value: colProvider),
      ],
      child: BlockMusicApp(initialSong: lastSong),
    ),
  );
}

class BlockMusicApp extends StatelessWidget {
  final Song? initialSong;
  const BlockMusicApp({super.key, this.initialSong});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlockMusic',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: HomeScreen(initialSong: initialSong),
    );
  }
}
