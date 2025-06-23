import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class MapConfig {
  static const String _tiandituKeyKey = 'tianditu_api_key';
  static const String _defaultTiandituKey = '你的天地图密钥';
  
  static String _tiandituApiKey = _defaultTiandituKey;
  
  // 获取天地图API密钥
  static String get tiandituApiKey => _tiandituApiKey;
  
  // 设置天地图API密钥
  static Future<void> setTiandituApiKey(String key) async {
    _tiandituApiKey = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tiandituKeyKey, key);
      debugPrint('天地图API密钥已保存');
    } catch (e) {
      debugPrint('保存天地图API密钥失败: $e');
    }
  }
  
  // 加载天地图API密钥
  static Future<void> loadTiandituApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_tiandituKeyKey);
      if (savedKey != null && savedKey.isNotEmpty && savedKey != _defaultTiandituKey) {
        _tiandituApiKey = savedKey;
        debugPrint('天地图API密钥已加载');
      }
    } catch (e) {
      debugPrint('加载天地图API密钥失败: $e');
    }
  }
  
  // 检查天地图API密钥是否有效
  static bool get isTiandituKeyValid {
    return _tiandituApiKey.isNotEmpty && _tiandituApiKey != _defaultTiandituKey;
  }
  
  // 获取带密钥的天地图URL
  static String getTiandituUrl(String baseUrl) {
    if (!isTiandituKeyValid) {
      return baseUrl.replaceAll('tk=你的天地图密钥', 'tk=');
    }
    return baseUrl.replaceAll('tk=你的天地图密钥', 'tk=$_tiandituApiKey');
  }
} 