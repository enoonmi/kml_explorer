import 'dart:io';
import 'dart:convert';
import 'dart:math' show min, max, log;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import 'kml_parser.dart';
import 'kml_marker.dart';
import '../utils/coord_transform.dart';
import '../services/webdav_service.dart';

class KmlFile {
  final String name;
  final String filePath;
  final DateTime importDate;
  final List<TrackPoint> points;
  final List<KmlMarker> markers;
  final bool isVisible;
  
  // 新增轨迹样式属性
  final String displayName;
  final Color trackColor;
  final double trackWidth;
  final int startPointIndex;
  final int endPointIndex;
  
  // 新增KML解析属性
  final String trackName;
  final List<String> trackTags;
  final bool isCloudSaved; // 新增：云端保存状态

  KmlFile({
    required this.name,
    required this.filePath,
    required this.importDate,
    required this.points,
    List<KmlMarker>? markers,
    this.isVisible = true,
    String? displayName,
    Color? trackColor,
    double? trackWidth,
    int? startPointIndex,
    int? endPointIndex,
    String? trackName,
    List<String>? trackTags,
    this.isCloudSaved = false, // 新增：默认未保存到云端
  }) : 
    markers = markers ?? [],
    displayName = displayName ?? trackName ?? name,
    trackColor = trackColor ?? const Color(0xFF2196F3),
    trackWidth = trackWidth ?? 3.0,
    startPointIndex = startPointIndex ?? 0,
    endPointIndex = endPointIndex ?? (points.length - 1),
    trackName = trackName ?? '',
    trackTags = trackTags ?? [];

  // 获取当前显示的轨迹点（WGS-84坐标系）
  List<LatLng> get visiblePoints {
    if (points.isEmpty) return [];
    final start = startPointIndex.clamp(0, points.length - 1);
    final end = endPointIndex.clamp(start, points.length - 1);
    return points.sublist(start, end + 1).map((p) => p.toLatLng()).toList();
  }

  // 获取转换后的轨迹点（根据地图类型自动转换坐标系）
  List<LatLng> getVisiblePointsForMap(bool isChineseMap) {
    final wgs84Points = visiblePoints;
    if (!isChineseMap) {
      // 国外地图使用WGS-84坐标系，无需转换
      return wgs84Points;
    } else {
      // 国内地图需要转换为GCJ-02坐标系
      return CoordTransform.transformTrackPoints(wgs84Points, true);
    }
  }

  // 获取转换后的标记点（根据地图类型自动转换坐标系）
  List<KmlMarker> getMarkersForMap(bool isChineseMap) {
    return markers.map((marker) {
      if (isChineseMap) {
        // 国内地图需要转换为GCJ-02坐标系
        final transformedPosition = CoordTransform.wgs84ToGcj02(marker.position);
        return KmlMarker(
          id: marker.id,
          name: marker.name,
          description: marker.description,
          position: transformedPosition,
          altitude: marker.altitude,
          timestamp: marker.timestamp,
          speed: marker.speed,
          imageUrl: marker.imageUrl,
          imageFileName: marker.imageFileName,
          imageFileId: marker.imageFileId,
          extendedData: marker.extendedData,
        );
      } else {
        // 国外地图使用WGS-84坐标系，无需转换
        return marker;
      }
    }).toList();
  }

  // 获取轨迹边界
  Map<String, double> get bounds {
    if (visiblePoints.isEmpty) {
      return {
        'minLat': 0.0, 'maxLat': 0.0,
        'minLng': 0.0, 'maxLng': 0.0,
      };
    }

    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    // 遍历所有可见点，确保找到真正的边界
    for (var point in visiblePoints) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return {
      'minLat': minLat, 'maxLat': maxLat,
      'minLng': minLng, 'maxLng': maxLng,
    };
  }

  // 获取轨迹的精确边界（包含边距）
  Map<String, double> get boundsWithPadding {
    final bounds = this.bounds;
    if (bounds['minLat'] == 0.0 && bounds['maxLat'] == 0.0) {
      return bounds;
    }

    // 计算轨迹的跨度
    final latSpan = bounds['maxLat']! - bounds['minLat']!;
    final lngSpan = bounds['maxLng']! - bounds['minLng']!;
    
    // 添加15%的边距
    final latPadding = latSpan * 0.15;
    final lngPadding = lngSpan * 0.15;

    return {
      'minLat': bounds['minLat']! - latPadding,
      'maxLat': bounds['maxLat']! + latPadding,
      'minLng': bounds['minLng']! - lngPadding,
      'maxLng': bounds['maxLng']! + lngPadding,
    };
  }

  // 计算适合的缩放级别
  double get optimalZoom {
    final bounds = this.bounds;
    if (bounds['minLat'] == 0.0 && bounds['maxLat'] == 0.0) {
      return 15.0;
    }

    final latSpan = bounds['maxLat']! - bounds['minLat']!;
    final lngSpan = bounds['maxLng']! - bounds['minLng']!;
    final maxSpan = max(latSpan, lngSpan);

    if (maxSpan <= 0) return 15.0;

    // 使用更精确的缩放计算公式
    // 基于地球周长和地图瓦片系统
    const double earthCircumference = 40075016.686; // 地球周长（米）
    
    // 计算适合的缩放级别
    double zoom = log(earthCircumference / (maxSpan * 111320)) / log(2);
    
    
    // 限制在合理范围内
    return zoom.clamp(3.0, 18.0);
  }

  // 复制并修改属性
  KmlFile copyWith({
    String? name,
    String? filePath,
    DateTime? importDate,
    List<TrackPoint>? points,
    List<KmlMarker>? markers,
    bool? isVisible,
    String? displayName,
    Color? trackColor,
    double? trackWidth,
    int? startPointIndex,
    int? endPointIndex,
    String? trackName,
    List<String>? trackTags,
    bool? isCloudSaved, // 新增
  }) {
    return KmlFile(
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      importDate: importDate ?? this.importDate,
      points: points ?? this.points,
      markers: markers ?? this.markers,
      isVisible: isVisible ?? this.isVisible,
      displayName: displayName ?? this.displayName,
      trackColor: trackColor ?? this.trackColor,
      trackWidth: trackWidth ?? this.trackWidth,
      startPointIndex: startPointIndex ?? this.startPointIndex,
      endPointIndex: endPointIndex ?? this.endPointIndex,
      trackName: trackName ?? this.trackName,
      trackTags: trackTags ?? this.trackTags,
      isCloudSaved: isCloudSaved ?? this.isCloudSaved, // 新增
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'filePath': filePath,
      'importDate': importDate.toIso8601String(),
      'points': points.map((point) => [
        point.latitude, 
        point.longitude, 
        point.altitude,
        point.timestamp.toIso8601String(),
        point.speed,
      ]).toList(),
      'markers': markers.map((marker) => [
        marker.id,
        marker.name,
        marker.description,
        marker.position.latitude,
        marker.position.longitude,
        marker.altitude,
        marker.timestamp.toIso8601String(),
        marker.speed,
        marker.imageUrl,
        marker.imageFileName,
        marker.imageFileId,
        marker.extendedData,
      ]).toList(),
      'isVisible': isVisible,
      'displayName': displayName,
      'trackColor': trackColor.toARGB32(),
      'trackWidth': trackWidth,
      'startPointIndex': startPointIndex,
      'endPointIndex': endPointIndex,
      'trackName': trackName,
      'trackTags': trackTags,
      'isCloudSaved': isCloudSaved, // 新增
    };
  }

  factory KmlFile.fromJson(Map<String, dynamic> json) {
    return KmlFile(
      name: json['name'],
      filePath: json['filePath'],
      importDate: DateTime.parse(json['importDate']),
      points: (json['points'] as List).map((point) {
        if (point.length >= 5) {
          // 新格式：包含海拔、时间戳和速度
          return TrackPoint(
            latitude: point[0],
            longitude: point[1],
            altitude: point[2],
            timestamp: DateTime.parse(point[3]),
            speed: point[4],
          );
        } else if (point.length >= 4) {
          // 包含海拔和时间戳
          return TrackPoint(
            latitude: point[0],
            longitude: point[1],
            altitude: point[2],
            timestamp: DateTime.parse(point[3]),
          );
        } else {
          // 旧格式：只有经纬度
          return TrackPoint(
            latitude: point[0],
            longitude: point[1],
            altitude: 0.0,
            timestamp: DateTime.now(),
          );
        }
      }).toList(),
      markers: (json['markers'] as List).map((marker) {
        // 修复extendedData类型转换问题
        Map<String, String> extendedData = {};
        if (marker.length > 11 && marker[11] != null) {
          final rawExtendedData = marker[11] as Map<String, dynamic>;
          extendedData = rawExtendedData.map((key, value) => MapEntry(key, value.toString()));
        }
        
        return KmlMarker(
          id: marker[0],
          name: marker[1],
          description: marker[2],
          position: LatLng(marker[3], marker[4]),
          altitude: marker[5],
          timestamp: DateTime.parse(marker[6]),
          speed: marker[7],
          imageUrl: marker[8],
          imageFileName: marker[9],
          imageFileId: marker[10],
          extendedData: extendedData,
        );
      }).toList(),
      isVisible: json['isVisible'] ?? true,
      displayName: json['displayName'],
      trackColor: Color(json['trackColor'] ?? 0xFF2196F3),
      trackWidth: json['trackWidth']?.toDouble() ?? 3.0,
      startPointIndex: json['startPointIndex'] ?? 0,
      endPointIndex: json['endPointIndex'],
      trackName: json['trackName'] ?? '',
      trackTags: json['trackTags'] != null 
          ? List<String>.from(json['trackTags'])
          : [],
      isCloudSaved: json['isCloudSaved'] ?? false, // 新增
    );
  }
}

class KmlFileManager {
  static Future<String> get _metadataPath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/kml_files_metadata.json';
  }

  static Future<String> get _kmlDirectory async {
    final directory = await getApplicationDocumentsDirectory();
    final kmlDir = Directory('${directory.path}/kml_files');
    if (!await kmlDir.exists()) {
      await kmlDir.create(recursive: true);
    }
    return kmlDir.path;
  }

  static Future<List<KmlFile>> loadKmlFiles() async {
    try {
      final metadataPath = await _metadataPath;
      final metadataFile = File(metadataPath);
      
      if (!await metadataFile.exists()) {
        return [];
      }

      try {
        final jsonString = await metadataFile.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        
        List<KmlFile> files = [];
        for (var json in jsonList) {
          try {
            files.add(KmlFile.fromJson(json));
          } catch (e) {
            debugPrint('KmlFileManager: 解析KML文件元数据时出错: $e');
          }
        }
        
        return files;
      } catch (e) {
        debugPrint('KmlFileManager: JSON解析失败，尝试恢复备份: $e');
        // 尝试恢复备份
        return await _tryRestoreFromBackup();
      }
    } catch (e) {
      debugPrint('KmlFileManager: 加载KML文件列表时出错: $e');
      return [];
    }
  }

  // 尝试从备份恢复
  static Future<List<KmlFile>> _tryRestoreFromBackup() async {
    try {
      final metadataPath = await _metadataPath;
      final backupPath = '${metadataPath}_backup';
      final backupFile = File(backupPath);
      
      if (await backupFile.exists()) {
        debugPrint('KmlFileManager: 尝试从备份文件恢复');
        final jsonString = await backupFile.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        
        List<KmlFile> files = [];
        for (var json in jsonList) {
          try {
            files.add(KmlFile.fromJson(json));
          } catch (e) {
            debugPrint('KmlFileManager: 从备份解析KML文件元数据时出错: $e');
          }
        }
        
        // 恢复成功后，将备份复制为主文件
        await backupFile.copy(metadataPath);
        debugPrint('KmlFileManager: 从备份恢复成功，文件数量: ${files.length}');
        return files;
      } else {
        debugPrint('KmlFileManager: 备份文件不存在，返回空列表');
        return [];
      }
    } catch (e) {
      debugPrint('KmlFileManager: 从备份恢复失败: $e');
      return [];
    }
  }

  static Future<void> saveKmlFile(File file) async {
    try {
      final kmlDir = await _kmlDirectory;
      final fileName = _sanitizeFileName(file.path.split(Platform.pathSeparator).last);
      final targetPath = '$kmlDir/$fileName';

      // 检查是否已存在同名文件，若存在则不导入
      if (await File(targetPath).exists()) {
        debugPrint('文件已存在，跳过导入: $fileName');
        return;
      }
      
      // 复制文件
      await file.copy(targetPath);
      
      // 解析KML内容
      final content = await file.readAsString();
      final parseResult = KmlParser.parseKmlFile(content);
      
      final points = parseResult['points'] as List<TrackPoint>;
      final markers = parseResult['markers'] as List<KmlMarker>;
      final trackName = parseResult['name'] as String;
      final trackTags = parseResult['tags'] as List<String>;
      final trackColor = parseResult['trackColor'] as Color? ?? const Color(0xFF2196F3);
      final trackWidth = parseResult['trackWidth'] as double? ?? 3.0;
      
      // 创建KmlFile对象
      final kmlFile = KmlFile(
        name: fileName,
        filePath: targetPath,
        importDate: DateTime.now(),
        points: points,
        markers: markers,
        trackName: trackName,
        trackTags: trackTags,
        trackColor: trackColor,
        trackWidth: trackWidth,
        isCloudSaved: false, // 新导入的文件默认未保存到云端
      );
      
      // 保存元数据
      await _saveMetadata(kmlFile);
      
      // 自动上传到WebDAV
      await _autoUploadToWebDav(kmlFile);
      
    } catch (e) {
      debugPrint('保存KML文件失败: $e');
      rethrow;
    }
  }

  // 新增：专门用于WebDAV下载的保存方法，保持原始文件名
  static Future<void> saveKmlFileFromWebDav(File file, String originalFileName) async {
    try {
      final kmlDir = await _kmlDirectory;
      final fileName = _sanitizeFileName(originalFileName);
      final targetPath = '$kmlDir/$fileName';

      // 检查是否已存在同名文件，若存在则不导入
      if (await File(targetPath).exists()) {
        debugPrint('文件已存在，跳过导入: $fileName');
        return;
      }
      
      // 复制文件
      await file.copy(targetPath);
      
      // 解析KML内容
      final content = await file.readAsString();
      final parseResult = KmlParser.parseKmlFile(content);
      
      final points = parseResult['points'] as List<TrackPoint>;
      final markers = parseResult['markers'] as List<KmlMarker>;
      final trackName = parseResult['name'] as String;
      final trackTags = parseResult['tags'] as List<String>;
      final trackColor = parseResult['trackColor'] as Color? ?? const Color(0xFF2196F3);
      final trackWidth = parseResult['trackWidth'] as double? ?? 3.0;
      
      // 创建KmlFile对象
      final kmlFile = KmlFile(
        name: fileName,
        filePath: targetPath,
        importDate: DateTime.now(),
        points: points,
        markers: markers,
        trackName: trackName,
        trackTags: trackTags,
        trackColor: trackColor,
        trackWidth: trackWidth,
        isCloudSaved: true, // WebDAV下载的文件默认已保存到云端
      );
      
      // 保存元数据
      await _saveMetadata(kmlFile);
      
      debugPrint('WebDAV文件保存成功: $fileName');
      
    } catch (e) {
      debugPrint('保存WebDAV KML文件失败: $e');
      rethrow;
    }
  }

  static Future<void> updateFileVisibility(String fileName, bool isVisible) async {
    try {
      debugPrint('KmlFileManager: 更新文件可见性: $fileName -> $isVisible');
      final files = await loadKmlFiles();
      final index = files.indexWhere((file) => file.name == fileName);
      
      if (index != -1) {
        debugPrint('KmlFileManager: 找到文件，更新可见性');
        files[index] = files[index].copyWith(isVisible: isVisible);
        await _saveMetadataList(files);
        debugPrint('KmlFileManager: 文件可见性更新成功');
      } else {
        debugPrint('KmlFileManager: 未找到文件: $fileName');
      }
    } catch (e) {
      debugPrint('KmlFileManager: 更新文件可见性时出错: $e');
      rethrow;
    }
  }

  static Future<void> updateFileStyle(String fileName, {
    String? displayName,
    Color? trackColor,
    double? trackWidth,
    int? startPointIndex,
    int? endPointIndex,
  }) async {
    try {
      final metadataPath = await _metadataPath;
      final metadataFile = File(metadataPath);
      
      if (!await metadataFile.exists()) {
        debugPrint('元数据文件不存在');
        return;
      }

      // 读取现有元数据
      final jsonString = await metadataFile.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);
      
      // 查找并更新指定文件
      bool found = false;
      for (int i = 0; i < jsonList.length; i++) {
        final fileData = jsonList[i] as Map<String, dynamic>;
        if (fileData['name'] == fileName) {
          // 只更新需要修改的字段，保留其他字段
          if (displayName != null) fileData['displayName'] = displayName;
          if (trackColor != null) fileData['trackColor'] = trackColor.toARGB32();
          if (trackWidth != null) fileData['trackWidth'] = trackWidth;
          if (startPointIndex != null) fileData['startPointIndex'] = startPointIndex;
          if (endPointIndex != null) fileData['endPointIndex'] = endPointIndex;
          
          found = true;
          break;
        }
      }
      
      if (found) {
        // 保存更新后的元数据
        final updatedJsonString = json.encode(jsonList);
        await metadataFile.writeAsString(updatedJsonString);
        debugPrint('文件样式更新成功: $fileName');
      } else {
        debugPrint('未找到要更新的文件: $fileName');
      }
    } catch (e) {
      debugPrint('更新文件样式时出错: $e');
      rethrow;
    }
  }

  static Future<void> deleteKmlFile(String fileName) async {
    try {
      final files = await loadKmlFiles();
      final fileToDelete = files.firstWhere((file) => file.name == fileName);
      
      // 删除文件
      final file = File(fileToDelete.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // 更新元数据
      files.removeWhere((file) => file.name == fileName);
      await _saveMetadataList(files);
      
    } catch (e) {
      debugPrint('删除KML文件时出错: $e');
      rethrow;
    }
  }

  static Future<void> _saveMetadata(KmlFile kmlFile) async {
    try {
      final files = await loadKmlFiles();
      final index = files.indexWhere((file) => file.name == kmlFile.name);
      
      if (index != -1) {
        files[index] = kmlFile;
      } else {
        files.add(kmlFile);
      }
      
      await _saveMetadataList(files);
    } catch (e) {
      debugPrint('保存元数据时出错: $e');
      rethrow;
    }
  }

  static Future<void> _saveMetadataList(List<KmlFile> files) async {
    try {
      debugPrint('KmlFileManager: 保存元数据列表，文件数量: ${files.length}');
      final metadataPath = await _metadataPath;
      final backupPath = '${metadataPath}_backup';
      
      // 创建备份
      final metadataFile = File(metadataPath);
      if (await metadataFile.exists()) {
        await metadataFile.copy(backupPath);
        debugPrint('KmlFileManager: 创建备份文件');
      }
      
      // 准备JSON数据
      final jsonList = files.map((file) => file.toJson()).toList();
      final jsonString = json.encode(jsonList);
      
      // 先写入临时文件，然后重命名，确保原子性写入
      final tempPath = '${metadataPath}_temp';
      final tempFile = File(tempPath);
      await tempFile.writeAsString(jsonString);
      
      // 原子性重命名
      await tempFile.rename(metadataPath);
      
      debugPrint('KmlFileManager: 元数据列表保存成功');
    } catch (e) {
      debugPrint('KmlFileManager: 保存元数据列表时出错: $e');
      rethrow;
    }
  }

  static String _sanitizeFileName(String fileName) {
    // 清理文件名，移除特殊字符
    return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  // 新增：自动上传到WebDAV
  static Future<void> _autoUploadToWebDav(KmlFile kmlFile) async {
    try {
      final webDavService = WebDavService.instance;
      if (webDavService.isEnabled && !kmlFile.isCloudSaved) {
        // 只有未保存到云端的文件才自动上传
        final file = File(kmlFile.filePath);
        final success = await webDavService.uploadFile(file, kmlFile.name);
        
        if (success) {
          // 更新云端状态
          await updateCloudStatus(kmlFile.name, true);
          debugPrint('文件自动上传到WebDAV成功: ${kmlFile.name}');
        } else {
          debugPrint('文件自动上传到WebDAV失败: ${kmlFile.name}');
        }
      } else if (kmlFile.isCloudSaved) {
        debugPrint('文件已保存到云端，跳过自动上传: ${kmlFile.name}');
      }
    } catch (e) {
      debugPrint('自动上传到WebDAV时出错: $e');
    }
  }

  // 新增：更新云端保存状态
  static Future<void> updateCloudStatus(String fileName, bool isCloudSaved) async {
    try {
      final metadataPath = await _metadataPath;
      final metadataFile = File(metadataPath);
      
      if (!await metadataFile.exists()) {
        debugPrint('元数据文件不存在');
        return;
      }

      // 读取现有元数据
      final jsonString = await metadataFile.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);
      
      // 查找并更新指定文件
      bool found = false;
      for (int i = 0; i < jsonList.length; i++) {
        final fileData = jsonList[i] as Map<String, dynamic>;
        if (fileData['name'] == fileName) {
          fileData['isCloudSaved'] = isCloudSaved;
          found = true;
          break;
        }
      }
      
      if (found) {
        // 保存更新后的元数据
        final updatedJsonString = json.encode(jsonList);
        await metadataFile.writeAsString(updatedJsonString);
        debugPrint('云端状态更新成功: $fileName');
      } else {
        debugPrint('未找到要更新的文件: $fileName');
      }
    } catch (e) {
      debugPrint('更新云端状态时出错: $e');
      rethrow;
    }
  }

  // 清理损坏的元数据文件
  static Future<void> clearCorruptedMetadata() async {
    try {
      final metadataPath = await _metadataPath;
      final backupPath = '${metadataPath}_backup';
      final tempPath = '${metadataPath}_temp';
      
      // 删除所有相关文件
      final files = [metadataPath, backupPath, tempPath];
      for (final path in files) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('KmlFileManager: 删除文件: $path');
        }
      }
      
      debugPrint('KmlFileManager: 损坏的元数据文件已清理');
    } catch (e) {
      debugPrint('KmlFileManager: 清理损坏文件时出错: $e');
    }
  }

  // 手动恢复备份
  static Future<bool> restoreFromBackup() async {
    try {
      final metadataPath = await _metadataPath;
      final backupPath = '${metadataPath}_backup';
      final backupFile = File(backupPath);
      
      if (await backupFile.exists()) {
        await backupFile.copy(metadataPath);
        debugPrint('KmlFileManager: 手动恢复备份成功');
        return true;
      } else {
        debugPrint('KmlFileManager: 备份文件不存在');
        return false;
      }
    } catch (e) {
      debugPrint('KmlFileManager: 手动恢复备份失败: $e');
      return false;
    }
  }
} 