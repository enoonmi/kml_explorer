import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

/// KML标记点模型
class KmlMarker {
  final String id;
  final String name;
  final String description;
  final LatLng position;
  final double altitude;
  final DateTime timestamp;
  final double speed;
  final String? imageUrl;
  final String? imageFileName;
  final String? imageFileId;
  final Map<String, String> extendedData;

  KmlMarker({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
    required this.altitude,
    required this.timestamp,
    required this.speed,
    this.imageUrl,
    this.imageFileName,
    this.imageFileId,
    required this.extendedData,
  });

  /// 从XML元素创建KmlMarker
  factory KmlMarker.fromXmlElement(XmlElement element) {
    final id = element.getAttribute('id') ?? '';
    final name = _getElementText(element, 'name') ?? '';
    final description = _getElementText(element, 'description') ?? '';
    
    // 解析ExtendedData
    final extendedData = <String, String>{};
    final extendedDataElements = element.findElements('ExtendedData');
    if (extendedDataElements.isNotEmpty) {
      final dataElements = extendedDataElements.first.findElements('Data');
      for (final dataElement in dataElements) {
        final name = dataElement.getAttribute('name');
        final valueElements = dataElement.findElements('value');
        final value = valueElements.isNotEmpty ? valueElements.first.innerText : '';
        if (name != null) {
          extendedData[name] = value;
        }
      }
    }
    
    // 优先从ExtendedData中解析坐标
    LatLng position = const LatLng(0, 0);
    double altitude = 0.0;
    
    final latValue = extendedData['Latitude'];
    final lngValue = extendedData['Longtitude'];
    final altValue = extendedData['Altitude'];
    
    if (latValue != null && lngValue != null) {
      final lat = double.tryParse(latValue);
      final lng = double.tryParse(lngValue);
      if (lat != null && lng != null) {
        position = LatLng(lat, lng);
      }
    }
    
    if (altValue != null) {
      altitude = double.tryParse(altValue) ?? 0.0;
    }
    
    // 如果ExtendedData中没有坐标，尝试从Point元素解析
    if (position.latitude == 0 && position.longitude == 0) {
      final pointElements = element.findElements('Point');
      if (pointElements.isNotEmpty) {
        final coordElements = pointElements.first.findElements('coordinates');
        if (coordElements.isNotEmpty) {
          final coordinates = coordElements.first.innerText;
          final coords = coordinates.split(',').map((s) => double.tryParse(s.trim()) ?? 0.0).toList();
          if (coords.length >= 2) {
            position = LatLng(coords[1], coords[0]);
          }
          if (coords.length >= 3) {
            altitude = coords[2];
          }
        }
      }
    }
    
    // 如果还是没有坐标，尝试从description中解析
    if (position.latitude == 0 && position.longitude == 0) {
      final latMatch = RegExp(r'纬度：([0-9.-]+)').firstMatch(description);
      final lngMatch = RegExp(r'经度：([0-9.-]+)').firstMatch(description);
      final altMatch = RegExp(r'海拔：([0-9.-]+)').firstMatch(description);
      
      if (latMatch != null && lngMatch != null) {
        final lat = double.tryParse(latMatch.group(1) ?? '');
        final lng = double.tryParse(lngMatch.group(1) ?? '');
        if (lat != null && lng != null) {
          position = LatLng(lat, lng);
        }
      }
      
      if (altMatch != null) {
        altitude = double.tryParse(altMatch.group(1) ?? '') ?? 0.0;
      }
    }
    
    // 解析时间戳
    DateTime timestamp = DateTime.now();
    final timeValue = extendedData['Time'];
    if (timeValue != null) {
      final timeMillis = int.tryParse(timeValue);
      if (timeMillis != null) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timeMillis);
      }
    } else {
      // 如果ExtendedData中没有时间，尝试从description中解析
      final timeMatch = RegExp(r'时间：([0-9-]+ [0-9:]+)').firstMatch(description);
      if (timeMatch != null) {
        try {
          timestamp = DateTime.parse(timeMatch.group(1) ?? '');
        } catch (e) {
          // 忽略解析错误
        }
      }
    }
    
    // 解析速度
    final speedValue = extendedData['Speed'];
    final speed = double.tryParse(speedValue ?? '0') ?? 0.0;
    
    // 解析图片信息
    String? imageUrl;
    String? imageFileName;
    String? imageFileId;
    
    // 从description中提取图片URL
    if (description.contains('img')) {
      final imgMatch = RegExp(r'src="([^"]+)"').firstMatch(description);
      if (imgMatch != null) {
        imageUrl = imgMatch.group(1);
        // URL解码
        if (imageUrl != null) {
          imageUrl = Uri.decodeFull(imageUrl);
        }
      }
    }
    
    // 从ExtendedData中获取图片文件信息
    imageFileName = extendedData['FileName'];
    imageFileId = extendedData['FileId'];
    
    return KmlMarker(
      id: id,
      name: name.isNotEmpty ? name : '图片标记点',
      description: description,
      position: position,
      altitude: altitude,
      timestamp: timestamp,
      speed: speed,
      imageUrl: imageUrl,
      imageFileName: imageFileName,
      imageFileId: imageFileId,
      extendedData: extendedData,
    );
  }

  /// 获取元素文本内容
  static String? _getElementText(XmlElement element, String tagName) {
    final tagElements = element.findElements(tagName);
    if (tagElements.isNotEmpty) {
      return tagElements.first.innerText.trim();
    }
    return null;
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'position': [position.latitude, position.longitude],
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
      'imageUrl': imageUrl,
      'imageFileName': imageFileName,
      'imageFileId': imageFileId,
      'extendedData': extendedData,
    };
  }

  /// 从JSON创建KmlMarker
  factory KmlMarker.fromJson(Map<String, dynamic> json) {
    final positionData = json['position'] as List;
    final position = LatLng(positionData[0], positionData[1]);
    
    // 修复extendedData类型转换问题
    Map<String, String> extendedData = {};
    if (json['extendedData'] != null) {
      final rawExtendedData = json['extendedData'] as Map<String, dynamic>;
      extendedData = rawExtendedData.map((key, value) => MapEntry(key, value.toString()));
    }
    
    return KmlMarker(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      position: position,
      altitude: json['altitude']?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp']),
      speed: json['speed']?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl'],
      imageFileName: json['imageFileName'],
      imageFileId: json['imageFileId'],
      extendedData: extendedData,
    );
  }
} 