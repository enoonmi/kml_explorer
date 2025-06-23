import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // 检查并请求位置权限
  Future<bool> requestLocationPermission(BuildContext context) async {
    try {
      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          _showPermissionDialog(
            context,
            '位置服务未启用',
            '请在系统设置中启用位置服务，以便使用地图和导航功能。',
            '去设置',
            () => openAppSettings(),
          );
        }
        return false;
      }

      // 检查位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (context.mounted) {
            _showPermissionDialog(
              context,
              '位置权限被拒绝',
              '应用需要位置权限来显示当前位置和提供导航功能。',
              '重新请求',
              () => requestLocationPermission(context),
            );
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          _showPermissionDialog(
            context,
            '位置权限被永久拒绝',
            '位置权限已被永久拒绝，请在系统设置中手动启用。',
            '去设置',
            () => openAppSettings(),
          );
        }
        return false;
      }

      return permission == LocationPermission.whileInUse || 
             permission == LocationPermission.always;
    } catch (e) {
      debugPrint('请求位置权限失败: $e');
      return false;
    }
  }

  // 检查并请求存储权限
  Future<bool> requestStoragePermission(BuildContext context) async {
    try {
      if (await Permission.storage.isGranted) {
        return true;
      }

      if (await Permission.storage.isDenied) {
        PermissionStatus status = await Permission.storage.request();
        if (status.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(
              context,
              '存储权限被拒绝',
              '应用需要存储权限来读取和保存KML文件。',
              '重新请求',
              () => requestStoragePermission(context),
            );
          }
          return false;
        }
      }

      if (await Permission.storage.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDialog(
            context,
            '存储权限被永久拒绝',
            '存储权限已被永久拒绝，请在系统设置中手动启用。',
            '去设置',
            () => openAppSettings(),
          );
        }
        return false;
      }

      return await Permission.storage.isGranted;
    } catch (e) {
      debugPrint('请求存储权限失败: $e');
      return false;
    }
  }

  // 检查并请求相机权限
  Future<bool> requestCameraPermission(BuildContext context) async {
    try {
      if (await Permission.camera.isGranted) {
        return true;
      }

      if (await Permission.camera.isDenied) {
        PermissionStatus status = await Permission.camera.request();
        if (status.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(
              context,
              '相机权限被拒绝',
              '应用需要相机权限来拍摄照片并添加到地图标记中。',
              '重新请求',
              () => requestCameraPermission(context),
            );
          }
          return false;
        }
      }

      if (await Permission.camera.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDialog(
            context,
            '相机权限被永久拒绝',
            '相机权限已被永久拒绝，请在系统设置中手动启用。',
            '去设置',
            () => openAppSettings(),
          );
        }
        return false;
      }

      return await Permission.camera.isGranted;
    } catch (e) {
      debugPrint('请求相机权限失败: $e');
      return false;
    }
  }

  // 检查并请求照片库权限
  Future<bool> requestPhotosPermission(BuildContext context) async {
    try {
      if (await Permission.photos.isGranted) {
        return true;
      }

      if (await Permission.photos.isDenied) {
        PermissionStatus status = await Permission.photos.request();
        if (status.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(
              context,
              '照片库权限被拒绝',
              '应用需要照片库权限来选择图片作为地图标记。',
              '重新请求',
              () => requestPhotosPermission(context),
            );
          }
          return false;
        }
      }

      if (await Permission.photos.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDialog(
            context,
            '照片库权限被永久拒绝',
            '照片库权限已被永久拒绝，请在系统设置中手动启用。',
            '去设置',
            () => openAppSettings(),
          );
        }
        return false;
      }

      return await Permission.photos.isGranted;
    } catch (e) {
      debugPrint('请求照片库权限失败: $e');
      return false;
    }
  }

  // 检查网络权限（Android 13+需要）
  Future<bool> requestNetworkPermission(BuildContext context) async {
    try {
      if (await Permission.notification.isGranted) {
        return true;
      }

      if (await Permission.notification.isDenied) {
        PermissionStatus status = await Permission.notification.request();
        if (status.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(
              context,
              '通知权限被拒绝',
              '应用需要通知权限来显示网络状态变化。',
              '重新请求',
              () => requestNetworkPermission(context),
            );
          }
          return false;
        }
      }

      return await Permission.notification.isGranted;
    } catch (e) {
      debugPrint('请求网络权限失败: $e');
      return false;
    }
  }

  // 显示权限对话框
  void _showPermissionDialog(
    BuildContext context,
    String title,
    String message,
    String actionText,
    VoidCallback onAction,
  ) {
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onAction();
            },
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  // 检查所有必要权限
  Future<Map<String, bool>> checkAllPermissions(BuildContext context) async {
    if (!context.mounted) return {};
    final location = await requestLocationPermission(context);
    if (!context.mounted) return {};
    final storage = await requestStoragePermission(context);
    if (!context.mounted) return {};
    final camera = await requestCameraPermission(context);
    if (!context.mounted) return {};
    final photos = await requestPhotosPermission(context);
    if (!context.mounted) return {};
    final network = await requestNetworkPermission(context);
    if (!context.mounted) return {};
    return {
      'location': location,
      'storage': storage,
      'camera': camera,
      'photos': photos,
      'network': network,
    };
  }
}