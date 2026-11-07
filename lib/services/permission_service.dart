import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';

/// 定位权限申请的统一入口。
///
/// 调用顺序：定位服务开关 → 运行时权限 → Android 13+ 精确位置。
class PermissionService {
  PermissionService._();

  /// 检查并（必要时）申请定位权限。返回 true 表示可以开始定位。
  static Future<bool> checkAndRequestLocationPermission() async {
    // 1. 系统定位服务是否打开
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    // 2. 运行时权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // 3. Android 13+ 需要单独请求“精确位置”
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final status = await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'LocationWhenInUse',
        );
        // 用户只给了模糊位置时仍可用，只是精度低，因此不阻断流程。
        return status != LocationAccuracyStatus.reduced;
      }
    }

    return true;
  }

  /// 打开系统的定位设置页，供用户手动修复“定位服务已关闭”的情况。
  static Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }

  /// 打开本应用的权限设置页，供用户手动修复“永久拒绝”的情况。
  static Future<bool> openAppSettings() async {
    return Geolocator.openAppSettings();
  }
}
