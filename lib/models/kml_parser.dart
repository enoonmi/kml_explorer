import 'package:xml/xml.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'kml_marker.dart';

class TrackPoint {
  final double latitude;
  final double longitude;
  final double altitude;
  DateTime timestamp;
  final double? speed;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
    this.speed,
  });

  @override
  String toString() {
    return 'TrackPoint(lat: $latitude, lng: $longitude, alt: $altitude, time: $timestamp, speed: $speed)';
  }

  LatLng toLatLng() => LatLng(latitude, longitude);
}

class KmlParser {
  static Map<String, dynamic> parseKmlFile(String kmlContent) {
    List<TrackPoint> points = [];
    List<KmlMarker> markers = [];
    String trackName = '';
    List<String> trackTags = [];
    Color trackColor = const Color(0xFF2196F3); // 默认蓝色
    double trackWidth = 3.0; // 默认线宽

    try {
      final document = XmlDocument.parse(kmlContent);
      
      // 解析轨迹名称
      final nameElement = document.findAllElements('name').firstOrNull;
      if (nameElement != null) {
        trackName = nameElement.innerText.trim();
      }
      
      // 解析轨迹标签 - 从Document的ExtendedData中查找
      final documentElement = document.findAllElements('Document').firstOrNull;
      if (documentElement != null) {
        final extendedDataElement = documentElement.findElements('ExtendedData').firstOrNull;
        if (extendedDataElement != null) {
          final dataElements = extendedDataElement.findElements('Data');
          for (final dataElement in dataElements) {
            final name = dataElement.getAttribute('name');
            if (name == 'TrackTags') {
              final valueElement = dataElement.findElements('value').firstOrNull;
              if (valueElement != null) {
                final tagsText = valueElement.innerText.trim();
                if (tagsText.isNotEmpty) {
                  // 处理CDATA内容
                  final cleanText = tagsText.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
                  trackTags = cleanText.split(',').map((tag) => tag.trim()).toList();
                }
              }
            }
          }
        }
      }

      // 解析轨迹线样式（LineStringStyle 或 TrackStyle）
      // 优先查找LineStringStyle
      final styleList = document.findAllElements('Style').toList();
      XmlElement? styleElement;
      final lineStringStyles = styleList.where((e) => e.getAttribute('id') == 'LineStringStyle').toList();
      if (lineStringStyles.isNotEmpty) {
        styleElement = lineStringStyles.first;
      }
      if (styleElement != null) {
        final lineStyle = styleElement.findElements('LineStyle').firstOrNull;
        if (lineStyle != null) {
          // 解析颜色
          final colorElement = lineStyle.findElements('color').firstOrNull;
          if (colorElement != null) {
            final kmlColor = colorElement.innerText.trim();
            if (kmlColor.length == 8) {
              // KML颜色格式为AABBGGRR
              final a = int.parse(kmlColor.substring(0, 2), radix: 16);
              final b = int.parse(kmlColor.substring(2, 4), radix: 16);
              final g = int.parse(kmlColor.substring(4, 6), radix: 16);
              final r = int.parse(kmlColor.substring(6, 8), radix: 16);
              trackColor = Color.fromARGB(a, r, g, b);
            }
          }
          // 解析线宽
          final widthElement = lineStyle.findElements('width').firstOrNull;
          if (widthElement != null) {
            final width = double.tryParse(widthElement.innerText.trim());
            if (width != null) {
              trackWidth = width;
            }
          }
        }
      } else {
        // 如果没有LineStringStyle，尝试TrackStyle_n
        final trackStyleList = styleList.where((e) => e.getAttribute('id') == 'TrackStyle_n').toList();
        XmlElement? trackStyleElement;
        if (trackStyleList.isNotEmpty) {
          trackStyleElement = trackStyleList.first;
        }
        if (trackStyleElement != null) {
          final lineStyle = trackStyleElement.findElements('LineStyle').firstOrNull;
          if (lineStyle != null) {
            final colorElement = lineStyle.findElements('color').firstOrNull;
            if (colorElement != null) {
              final kmlColor = colorElement.innerText.trim();
              if (kmlColor.length == 8) {
                final a = int.parse(kmlColor.substring(0, 2), radix: 16);
                final b = int.parse(kmlColor.substring(2, 4), radix: 16);
                final g = int.parse(kmlColor.substring(4, 6), radix: 16);
                final r = int.parse(kmlColor.substring(6, 8), radix: 16);
                trackColor = Color.fromARGB(a, r, g, b);
              }
            }
            final widthElement = lineStyle.findElements('width').firstOrNull;
            if (widthElement != null) {
              final width = double.tryParse(widthElement.innerText.trim());
              if (width != null) {
                trackWidth = width;
              }
            }
          }
        }
      }

      // 兼容旧格式：如果没有在Document的ExtendedData中找到，再尝试直接查找TrackTags元素
      if (trackTags.isEmpty) {
        final trackTagsElement = document.findAllElements('TrackTags').firstOrNull;
        if (trackTagsElement != null) {
          final tagsText = trackTagsElement.innerText.trim();
          if (tagsText.isNotEmpty) {
            trackTags = tagsText.split(',').map((tag) => tag.trim()).toList();
          }
        }
      }
      
      // 解析标记点和轨迹
      _parseDocument(document, points, markers);
      
      debugPrint('解析到 ${markers.length} 个标记点');
      debugPrint('解析到 ${points.length} 个轨迹点');
      debugPrint('最终结果: ${points.length} 个轨迹点（用于连线）, ${markers.length} 个标记点（独立显示）');
      
    } catch (e) {
      debugPrint('解析KML文件时出错: $e');
    }
    
    return {
      'points': points,
      'markers': markers,
      'name': trackName,
      'tags': trackTags,
      'trackColor': trackColor,
      'trackWidth': trackWidth,
    };
  }

  static void _parseDocument(XmlDocument document, List<TrackPoint> points, List<KmlMarker> markers) {
    // 只解析Document下的直接Placemark（不在Folder中的）
    final documentElement = document.findAllElements('Document').firstOrNull;
    if (documentElement != null) {
      final directPlacemarks = documentElement.findElements('Placemark');
      for (final placemark in directPlacemarks) {
        _parsePlacemark(placemark, points, markers);
      }
      
      // 解析所有Folder
      final folders = documentElement.findElements('Folder');
      for (final folder in folders) {
        _parseFolder(folder, points, markers);
      }
    } else {
      // 如果没有Document元素，则解析根级别的Placemark和Folder
      final placemarks = document.findAllElements('Placemark');
      for (final placemark in placemarks) {
        _parsePlacemark(placemark, points, markers);
      }
      
      final folders = document.findAllElements('Folder');
      for (final folder in folders) {
        _parseFolder(folder, points, markers);
      }
    }
  }

  static void _parseFolder(XmlElement folder, List<TrackPoint> points, List<KmlMarker> markers) {
    // 检查是否为标记点文件夹
    final folderName = _getElementText(folder, 'name');
    final isMarkerFolder = folderName.contains('标注点') || 
                          folderName.contains('markers') ||
                          folderName.contains('Markers') ||
                          folderName.contains('Points');
    
    // 解析文件夹中的Placemark
    final placemarks = folder.findElements('Placemark');
    for (final placemark in placemarks) {
      if (isMarkerFolder) {
        // 这是标记点文件夹，只解析点标记
        final pointElement = placemark.findElements('Point').firstOrNull;
        if (pointElement != null) {
          final marker = _createMarkerFromPlacemark(placemark);
          if (marker != null) {
            markers.add(marker);
          }
        }
      } else {
        // 这是轨迹文件夹，解析轨迹
        _parsePlacemark(placemark, points, markers);
      }
    }
    
    // 递归解析子文件夹
    final subFolders = folder.findElements('Folder');
    for (final subFolder in subFolders) {
      _parseFolder(subFolder, points, markers);
    }
  }

  static void _parsePlacemark(XmlElement placemark, List<TrackPoint> points, List<KmlMarker> markers) {
    // 检查几何体类型
    final pointElement = placemark.findElements('Point').firstOrNull;
    final lineStringElement = placemark.findElements('LineString').firstOrNull;
    final polygonElement = placemark.findElements('Polygon').firstOrNull;
    final multiGeometryElement = placemark.findElements('MultiGeometry').firstOrNull;
    final gxTrackElement = placemark.findElements('gx:Track').firstOrNull;
    final gxMultiTrackElement = placemark.findElements('gx:MultiTrack').firstOrNull;
    
    if (pointElement != null) {
      // 点标记
      final marker = _createMarkerFromPlacemark(placemark);
      if (marker != null) {
        markers.add(marker);
      }
    } else if (lineStringElement != null) {
      // 线轨迹
      final trackPoints = _createTrackPointsFromLineString(lineStringElement, placemark);
      points.addAll(trackPoints);
    } else if (gxTrackElement != null) {
      // gx:Track 轨迹（两步路等应用使用）
      final trackPoints = _createTrackPointsFromGxTrack(gxTrackElement, placemark);
      points.addAll(trackPoints);
    } else if (gxMultiTrackElement != null) {
      // gx:MultiTrack 多轨迹（KML 2.2 规范）
      final trackPoints = _createTrackPointsFromGxMultiTrack(gxMultiTrackElement, placemark);
      points.addAll(trackPoints);
    } else if (polygonElement != null) {
      // 多边形（通常不用于轨迹，但可能有外边界）
      final outerBoundaryElement = polygonElement.findElements('outerBoundaryIs').firstOrNull;
      if (outerBoundaryElement != null) {
        final linearRingElement = outerBoundaryElement.findElements('LinearRing').firstOrNull;
        if (linearRingElement != null) {
          final trackPoints = _createTrackPointsFromLineString(linearRingElement, placemark);
          points.addAll(trackPoints);
        }
      }
    } else if (multiGeometryElement != null) {
      // 复合几何体
      final geometries = multiGeometryElement.children.whereType<XmlElement>();
      for (final geometry in geometries) {
        if (geometry.name.local == 'LineString') {
          final trackPoints = _createTrackPointsFromLineString(geometry, placemark);
          points.addAll(trackPoints);
        } else if (geometry.name.local == 'Point') {
          final marker = _createMarkerFromPlacemark(placemark);
          if (marker != null) {
            markers.add(marker);
          }
        } else if (geometry.name.local == 'Track') {
          final trackPoints = _createTrackPointsFromGxTrack(geometry, placemark);
          points.addAll(trackPoints);
        } else if (geometry.name.local == 'MultiTrack') {
          final trackPoints = _createTrackPointsFromGxMultiTrack(geometry, placemark);
          points.addAll(trackPoints);
        }
      }
    }
  }

  static KmlMarker? _createMarkerFromPlacemark(XmlElement placemark) {
    try {
      // 检查是否为点标记
      final pointElement = placemark.findElements('Point').firstOrNull;
      if (pointElement == null) return null;
      
      // 解析坐标
      final coordinatesElement = pointElement.findElements('coordinates').firstOrNull;
      if (coordinatesElement == null) return null;
      
      final coordText = coordinatesElement.innerText.trim();
      final parts = coordText.split(',');
      if (parts.length < 2) return null;
      
      final lng = double.parse(parts[0]);
      final lat = double.parse(parts[1]);
      final alt = parts.length >= 3 ? double.parse(parts[2]) : 0.0;
      
      final position = LatLng(lat, lng);
      
      // 解析时间戳
      DateTime timestamp = DateTime.now();
      final timeStampElement = placemark.findElements('TimeStamp').firstOrNull;
      if (timeStampElement != null) {
        final whenElement = timeStampElement.findElements('when').firstOrNull;
        if (whenElement != null) {
          try {
            timestamp = DateTime.parse(whenElement.innerText.trim());
          } catch (e) {
            debugPrint('时间戳解析错误: $e');
          }
        }
      }
      
      // 解析扩展数据
      Map<String, String> extendedData = {};
      final extendedDataElement = placemark.findElements('ExtendedData').firstOrNull;
      if (extendedDataElement != null) {
        // 解析 Data 元素（标准格式）
        final dataElements = extendedDataElement.findElements('Data');
        for (final dataElement in dataElements) {
          final name = dataElement.getAttribute('name');
          final valueElement = dataElement.findElements('value').firstOrNull;
          if (name != null && valueElement != null) {
            extendedData[name] = valueElement.innerText.trim();
          }
        }
        
        // 解析 SimpleData 元素（KML 2.2 规范）
        final simpleDataElements = extendedDataElement.findElements('SimpleData');
        for (final simpleDataElement in simpleDataElements) {
          final name = simpleDataElement.getAttribute('name');
          if (name != null) {
            extendedData[name] = simpleDataElement.innerText.trim();
          }
        }
      }
      
      // 解析速度
      double speed = 0.0;
      final speedValue = extendedData['Speed'];
      if (speedValue != null) {
        speed = double.tryParse(speedValue) ?? 0.0;
      }
      
      // 解析图片信息
      String? imageUrl;
      String? imageFileName;
      String? imageFileId;
      
      // 从描述中提取图片URL
      final descriptionElement = placemark.findElements('description').firstOrNull;
      final description = descriptionElement?.innerText ?? '';
      if (description.contains('img')) {
        final imgMatch = RegExp(r'src="([^"]+)"').firstMatch(description);
        if (imgMatch != null) {
          imageUrl = imgMatch.group(1);
          if (imageUrl != null) {
            imageUrl = Uri.decodeFull(imageUrl);
          }
        }
      }
      
      // 从扩展数据中获取图片文件信息
      imageFileName = extendedData['FileName'];
      imageFileId = extendedData['FileId'];
      
      return KmlMarker(
        id: placemark.getAttribute('id') ?? '',
        name: _getElementText(placemark, 'name').isNotEmpty ? _getElementText(placemark, 'name') : '标记点',
        description: description,
        position: position,
        altitude: alt,
        timestamp: timestamp,
        speed: speed,
        imageUrl: imageUrl,
        imageFileName: imageFileName,
        imageFileId: imageFileId,
        extendedData: extendedData,
      );
    } catch (e) {
      debugPrint('创建标记点时出错: $e');
      return null;
    }
  }

  static List<TrackPoint> _createTrackPointsFromLineString(XmlElement lineStringElement, XmlElement placemark) {
    final points = <TrackPoint>[];
    final coordinatesElement = lineStringElement.findElements('coordinates').firstOrNull;
    
    if (coordinatesElement == null) return points;
    
    final coordText = coordinatesElement.innerText.trim();
    if (coordText.isEmpty) return points;
    
    final coordList = coordText.split(RegExp(r'\s+'));
    
    // 解析时间戳信息 - 支持 KML 2.2 规范
    DateTime? baseTime;
    
    // 首先尝试从 placemark 的 TimeStamp 获取时间戳
    final timeStampElement = placemark.findElements('TimeStamp').firstOrNull;
    if (timeStampElement != null) {
      final whenElement = timeStampElement.findElements('when').firstOrNull;
      if (whenElement != null) {
        try {
          baseTime = DateTime.parse(whenElement.innerText.trim());
        } catch (e) {
          debugPrint('TimeStamp时间戳解析错误: $e');
        }
      }
    }
    
    // 如果没有 TimeStamp，尝试从 TimeSpan 获取开始时间
    if (baseTime == null) {
      final timeSpanElement = placemark.findElements('TimeSpan').firstOrNull;
      if (timeSpanElement != null) {
        final beginElement = timeSpanElement.findElements('begin').firstOrNull;
        if (beginElement != null) {
          try {
            baseTime = DateTime.parse(beginElement.innerText.trim());
          } catch (e) {
            debugPrint('TimeSpan时间戳解析错误: $e');
          }
        }
      }
    }
    
    // 如果仍然没有时间戳，使用当前时间
    baseTime ??= DateTime.now();
    
    for (int i = 0; i < coordList.length; i++) {
      final point = coordList[i];
      if (point.isNotEmpty) {
        final parts = point.split(',');
        if (parts.length >= 2) {
          try {
            final lng = double.parse(parts[0]);
            final lat = double.parse(parts[1]);
            final alt = parts.length >= 3 ? double.parse(parts[2]) : 0.0;
            
            // 为每个点生成递增的时间戳
            final timestamp = baseTime.add(Duration(seconds: i * 30));
            
            points.add(TrackPoint(
              latitude: lat,
              longitude: lng,
              altitude: alt,
              timestamp: timestamp,
              speed: 0.0,
            ));
          } catch (e) {
            debugPrint('轨迹坐标解析错误: $point - $e');
          }
        }
      }
    }
    
    debugPrint('从LineString解析到 ${points.length} 个轨迹点');
    return points;
  }

  static List<TrackPoint> _createTrackPointsFromGxTrack(XmlElement gxTrackElement, XmlElement placemark) {
    final points = <TrackPoint>[];
    
    // 解析 gx:coord 元素（两步路格式）
    final gxCoordElements = gxTrackElement.findElements('gx:coord');
    if (gxCoordElements.isNotEmpty) {
      // 解析时间戳信息 - 支持 gx:when 元素（KML 2.2 规范）
      final whenElements = gxTrackElement.findElements('when');
      List<DateTime> timestamps = [];
      
      // 收集所有时间戳
      for (final whenElement in whenElements) {
        try {
          final timestamp = DateTime.parse(whenElement.innerText.trim());
          timestamps.add(timestamp);
        } catch (e) {
          debugPrint('时间戳解析错误: ${whenElement.innerText} - $e');
        }
      }
      
      // 如果没有时间戳，使用默认时间
      DateTime? baseTime;
      if (timestamps.isNotEmpty) {
        baseTime = timestamps.first;
      } else {
        // 尝试从 placemark 的 TimeStamp 获取基准时间
        final timeStampElement = placemark.findElements('TimeStamp').firstOrNull;
        if (timeStampElement != null) {
          final whenElement = timeStampElement.findElements('when').firstOrNull;
          if (whenElement != null) {
            try {
              baseTime = DateTime.parse(whenElement.innerText.trim());
            } catch (e) {
              debugPrint('时间戳解析错误: $e');
            }
          }
        }
        baseTime ??= DateTime.now();
      }
      
      for (int i = 0; i < gxCoordElements.length; i++) {
        final coordElement = gxCoordElements.elementAt(i);
        final coordText = coordElement.innerText.trim();
        
        if (coordText.isNotEmpty) {
          final parts = coordText.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            try {
              final lng = double.parse(parts[0]);
              final lat = double.parse(parts[1]);
              final alt = parts.length >= 3 ? double.parse(parts[2]) : 0.0;
              
              // 使用对应的时间戳，如果没有则生成递增时间戳
              DateTime timestamp;
              if (i < timestamps.length) {
                timestamp = timestamps[i];
              } else {
                timestamp = baseTime.add(Duration(seconds: i * 30));
              }
              
              points.add(TrackPoint(
                latitude: lat,
                longitude: lng,
                altitude: alt,
                timestamp: timestamp,
                speed: 0.0,
              ));
            } catch (e) {
              debugPrint('gx:coord解析错误: $coordText - $e');
            }
          }
        }
      }
      
      debugPrint('从gx:Track解析到 ${points.length} 个轨迹点，时间戳数量: ${timestamps.length}');
      return points;
    }
    
    // 如果没有 gx:coord 元素，尝试解析 coordinates 元素（标准格式）
    final coordinatesElement = gxTrackElement.findElements('coordinates').firstOrNull;
    if (coordinatesElement != null) {
      final coordText = coordinatesElement.innerText.trim();
      if (coordText.isNotEmpty) {
        final coordList = coordText.split(RegExp(r'\s+'));
        
        // 解析时间戳信息
        DateTime? baseTime;
        final timeStampElement = placemark.findElements('TimeStamp').firstOrNull;
        if (timeStampElement != null) {
          final whenElement = timeStampElement.findElements('when').firstOrNull;
          if (whenElement != null) {
            try {
              baseTime = DateTime.parse(whenElement.innerText.trim());
            } catch (e) {
              debugPrint('时间戳解析错误: $e');
            }
          }
        }
        
        // 如果没有时间戳，使用当前时间
        baseTime ??= DateTime.now();
        
        for (int i = 0; i < coordList.length; i++) {
          final point = coordList[i];
          if (point.isNotEmpty) {
            final parts = point.split(',');
            if (parts.length >= 2) {
              try {
                final lng = double.parse(parts[0]);
                final lat = double.parse(parts[1]);
                final alt = parts.length >= 3 ? double.parse(parts[2]) : 0.0;
                
                // 为每个点生成递增的时间戳
                final timestamp = baseTime.add(Duration(seconds: i * 30));
                
                points.add(TrackPoint(
                  latitude: lat,
                  longitude: lng,
                  altitude: alt,
                  timestamp: timestamp,
                  speed: 0.0,
                ));
              } catch (e) {
                debugPrint('轨迹坐标解析错误: $point - $e');
              }
            }
          }
        }
      }
    }
    
    debugPrint('从gx:Track解析到 ${points.length} 个轨迹点');
    return points;
  }

  static List<TrackPoint> _createTrackPointsFromGxMultiTrack(XmlElement gxMultiTrackElement, XmlElement placemark) {
    final points = <TrackPoint>[];
    
    // 解析 gx:MultiTrack 中的所有 gx:Track 元素
    final gxTrackElements = gxMultiTrackElement.findElements('gx:Track');
    
    for (final gxTrackElement in gxTrackElements) {
      final trackPoints = _createTrackPointsFromGxTrack(gxTrackElement, placemark);
      points.addAll(trackPoints);
    }
    
    debugPrint('从gx:MultiTrack解析到 ${points.length} 个轨迹点');
    return points;
  }

  static String _getElementText(XmlElement parent, String tagName) {
    final element = parent.findElements(tagName).firstOrNull;
    return element?.innerText.trim() ?? '';
  }
} 