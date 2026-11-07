import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/permission_service.dart';

/// 定位状态与位置更新流。
///
/// 从 `main.dart` 的 `_MapPageState` 里剥离出来，让 UI 只负责渲染。
class LocationController extends ChangeNotifier {
  LocationController({this.intervalSeconds = 5});

  /// 位置更新间隔，用户在「位置设置」里可调（1/3/5/10/30 秒）。
  int intervalSeconds;

  StreamSubscription<Position>? _subscription;

  LatLng? _position;
  double _accuracy = 0;
  double _speed = 0;
  double _heading = 0;
  DateTime? _lastUpdated;
  bool _isTracking = false;
  bool _isLoading = false;

  LatLng? get position => _position;
  double get accuracy => _accuracy;

  /// 速度，单位 m/s（展示时再换算 km/h）。
  double get speed => _speed;
  double get heading => _heading;
  DateTime? get lastUpdated => _lastUpdated;
  bool get isTracking => _isTracking;
  bool get isLoading => _isLoading;

  /// 按当前平台构造定位参数。
  ///
  /// 注意：`intervalDuration` 只存在于 AndroidSettings / AppleSettings，
  /// 通用 LocationSettings 没有该参数——这正是原先编译不过的原因。
  LocationSettings _buildSettings() {
    final interval = Duration(seconds: intervalSeconds);
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: interval,
        // 关闭强制 LocationManager，优先用 FusedLocationProvider，更省电。
        forceLocationManager: false,
      );
    }
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        allowBackgroundLocationUpdates: false,
        pauseLocationUpdatesAutomatically: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  /// 单次取当前位置。失败返回 null 并记录日志。
  Future<LatLng?> fetchCurrentPosition() async {
    _isLoading = true;
    notifyListeners();
    try {
      final granted = await PermissionService.checkAndRequestLocationPermission();
      if (!granted) return null;

      final position = await Geolocator.getCurrentPosition();
      _apply(position);
      return _position;
    } catch (e) {
      debugPrint('获取当前位置失败: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 开始持续定位。
  Future<bool> start() async {
    final granted = await PermissionService.checkAndRequestLocationPermission();
    if (!granted) return false;

    await _subscription?.cancel();
    _isTracking = true;
    notifyListeners();

    try {
      _subscription = Geolocator.getPositionStream(
        locationSettings: _buildSettings(),
      ).listen(
        _apply,
        onError: (Object error) {
          debugPrint('位置监听错误: $error');
          _isTracking = false;
          notifyListeners();
        },
      );
      return true;
    } catch (e) {
      debugPrint('启动定位失败: $e');
      _isTracking = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _isTracking = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_isTracking) {
      await stop();
    } else {
      await start();
    }
  }

  /// 修改更新间隔；若正在跟踪则重启流以立即生效。
  Future<void> setInterval(int seconds) async {
    intervalSeconds = seconds;
    if (_isTracking) {
      await stop();
      await start();
    } else {
      notifyListeners();
    }
  }

  void _apply(Position position) {
    _position = LatLng(position.latitude, position.longitude);
    _accuracy = position.accuracy;
    _speed = position.speed;
    _heading = position.heading;
    _lastUpdated = position.timestamp;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
