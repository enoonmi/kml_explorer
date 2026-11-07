import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/kml_file.dart';
import '../models/kml_marker.dart';

/// 把 [KmlFile] 列表编译成 flutter_map 可渲染的图层数据。
///
/// 坐标转换（WGS-84 → GCJ-02）与图层构建原先散落在 `main.dart` 里，
/// 每个调用点都要重复判断一次 `isChineseMap`；现在统一收在这里。
class TrackRenderer {
  const TrackRenderer._();

  /// 构建折线图层。
  static List<Polyline> buildPolylines(
    List<KmlFile> files, {
    required bool isChineseMap,
  }) {
    final polylines = <Polyline>[];
    for (final file in files) {
      if (!file.isVisible || file.visiblePoints.isEmpty) continue;
      polylines.add(
        Polyline(
          points: file.getVisiblePointsForMap(isChineseMap),
          color: file.trackColor,
          strokeWidth: file.trackWidth,
        ),
      );
    }
    return polylines;
  }

  /// 构建标注点图层。
  static List<Marker> buildMarkers(
    List<KmlFile> files, {
    required bool isChineseMap,
    required void Function(KmlMarker marker) onTap,
  }) {
    final markers = <Marker>[];
    for (final file in files) {
      if (!file.isVisible) continue;
      for (final marker in file.getMarkersForMap(isChineseMap)) {
        markers.add(_buildMarker(marker, onTap));
      }
    }
    return markers;
  }

  static Marker _buildMarker(KmlMarker marker, void Function(KmlMarker) onTap) {
    final isStartOrEnd = marker.name == '起点' || marker.name == '终点';
    final hasImage = marker.imageUrl != null || marker.imageFileName != null;

    final Color background;
    final IconData icon;
    if (hasImage) {
      background = Colors.red;
      icon = Icons.photo_camera;
    } else if (isStartOrEnd) {
      background = Colors.green;
      icon = Icons.play_arrow;
    } else {
      background = Colors.blue;
      icon = Icons.location_on;
    }

    return Marker(
      point: marker.position,
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => onTap(marker),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  /// 计算一组文件的合并包围盒，用于「查看当前轨迹」定位视野。
  ///
  /// 原先该计算在 `main.dart` 里被复制了多份，现在只留一处。
  static LatLngBounds? boundsOf(
    List<KmlFile> files, {
    required bool isChineseMap,
  }) {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    var hasPoint = false;

    for (final file in files) {
      if (!file.isVisible) continue;
      for (final p in file.getVisiblePointsForMap(isChineseMap)) {
        hasPoint = true;
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    if (!hasPoint) return null;

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  /// 依据包围盒反推合适的缩放级别。
  static double zoomForBounds(
    LatLngBounds bounds, {
    double inset = 0.3,
  }) {
    final latSpan = bounds.north - bounds.south;
    final lngSpan = bounds.east - bounds.west;
    final maxSpan = math.max(latSpan, lngSpan);
    if (maxSpan <= 0) return 15;

    const earthCircumference = 40075016.686;
    final zoom =
        math.log(earthCircumference / (maxSpan * 111320)) / math.ln2;
    return (zoom - inset).clamp(3.0, 18.0);
  }
}
