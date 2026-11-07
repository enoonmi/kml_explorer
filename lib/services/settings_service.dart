import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_config.dart';
import '../models/tile_server.dart';

/// 应用级设置的读写封装（基于 SharedPreferences）。
///
/// 把散落在 `main.dart` 里的 `prefs.getInt('tile_server_index')` 之类的
/// 魔法字符串集中到一处，避免键名写错后静默失效。
class SettingsService {
  SettingsService._();

  static const _kTileServerIndex = 'tile_server_index';
  static String _visibleKey(int index) => 'tile_server_visible_$index';
  static const _kLocationInterval = 'location_update_interval';
  static const _kShowFileManager = 'show_file_manager';

  /// 读取上次选择的地图供应商下标。
  static Future<int?> loadTileServerIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kTileServerIndex);
  }

  static Future<void> saveTileServerIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTileServerIndex, index);
  }

  /// 读取各供应商的可见性。返回 null 表示首次运行（尚未写入任何设置）。
  static Future<List<bool>?> loadTileVisibility(int count) async {
    final prefs = await SharedPreferences.getInstance();
    var firstTime = true;
    for (var i = 0; i < count; i++) {
      if (prefs.containsKey(_visibleKey(i))) {
        firstTime = false;
        break;
      }
    }
    if (firstTime) return null;

    return List<bool>.generate(
      count,
      (i) => prefs.getBool(_visibleKey(i)) ?? true,
    );
  }

  static Future<void> saveTileVisibility(List<TileServer> servers) async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < servers.length; i++) {
      await prefs.setBool(_visibleKey(i), servers[i].visible);
    }
  }

  /// 位置更新间隔（秒）。默认 5 秒。
  static Future<int> loadLocationInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLocationInterval) ?? 5;
  }

  static Future<void> saveLocationInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLocationInterval, seconds);
  }

  /// 桌面端文件面板是否展开。默认展开。
  static Future<bool> loadShowFileManager() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowFileManager) ?? true;
  }

  static Future<void> saveShowFileManager(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowFileManager, show);
  }

  /// 一次性加载启动所需设置，减少 await 往返。
  static Future<AppSettings> loadAll(int tileServerCount) async {
    final prefs = await SharedPreferences.getInstance();

    var firstTime = true;
    for (var i = 0; i < tileServerCount; i++) {
      if (prefs.containsKey(_visibleKey(i))) {
        firstTime = false;
        break;
      }
    }
    final visibility = firstTime
        ? List<bool>.filled(tileServerCount, true)
        : List<bool>.generate(
            tileServerCount,
            (i) => prefs.getBool(_visibleKey(i)) ?? true,
          );

    return AppSettings(
      tileServerIndex: prefs.getInt(_kTileServerIndex) ?? 0,
      tileVisibility: visibility,
      isFirstRun: firstTime,
      locationInterval: prefs.getInt(_kLocationInterval) ?? 5,
      showFileManager: prefs.getBool(_kShowFileManager) ?? true,
    );
  }

  /// 首次运行时把默认可见性落盘，供后续比较。
  static Future<void> persistFirstRunDefaults(List<TileServer> servers) async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < servers.length; i++) {
      await prefs.setBool(_visibleKey(i), servers[i].visible);
    }
    await prefs.setInt(_kTileServerIndex, 0);
    debugPrint('首次运行：已写入默认可见性设置');
  }

  /// 加载天地图 Key（兼容旧调用点）。
  static Future<void> loadMapConfig() => MapConfig.loadTiandituApiKey();
}

/// 启动时一次性读取出来的设置快照。
@immutable
class AppSettings {
  const AppSettings({
    required this.tileServerIndex,
    required this.tileVisibility,
    required this.isFirstRun,
    required this.locationInterval,
    required this.showFileManager,
  });

  final int tileServerIndex;
  final List<bool> tileVisibility;
  final bool isFirstRun;
  final int locationInterval;
  final bool showFileManager;
}
