import 'dart:math';
import 'package:latlong2/latlong.dart';

/// 坐标转换工具类
/// 实现WGS-84与GCJ-02坐标系之间的转换
class CoordTransform {
  static const double _pi = 3.14159265358979324;
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// WGS-84 转 GCJ-02
  static LatLng wgs84ToGcj02(LatLng wgs84) {
    double lat = wgs84.latitude;
    double lng = wgs84.longitude;
    
    if (_outOfChina(lat, lng)) {
      return wgs84;
    }
    
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);
    
    double radLat = lat / 180.0 * _pi;
    double magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    double sqrtMagic = sqrt(magic);
    
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * _pi);
    
    double mgLat = lat + dLat;
    double mgLng = lng + dLng;
    
    return LatLng(mgLat, mgLng);
  }

  /// GCJ-02 转 WGS-84
  static LatLng gcj02ToWgs84(LatLng gcj02) {
    double lat = gcj02.latitude;
    double lng = gcj02.longitude;
    
    if (_outOfChina(lat, lng)) {
      return gcj02;
    }
    
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);
    
    double radLat = lat / 180.0 * _pi;
    double magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    double sqrtMagic = sqrt(magic);
    
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * _pi);
    
    double mgLat = lat + dLat;
    double mgLng = lng + dLng;
    
    return LatLng(lat * 2 - mgLat, lng * 2 - mgLng);
  }

  /// 判断是否在中国境内
  static bool _outOfChina(double lat, double lng) {
    return !(lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55);
  }

  /// 转换纬度
  static double _transformLat(double x, double y) {
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * _pi) + 20.0 * sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * _pi) + 40.0 * sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * _pi) + 320 * sin(y * _pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  /// 转换经度
  static double _transformLng(double x, double y) {
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * _pi) + 20.0 * sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * _pi) + 40.0 * sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * _pi) + 300.0 * sin(x / 30.0 * _pi)) * 2.0 / 3.0;
    return ret;
  }

  /// 转换轨迹点列表
  static List<LatLng> transformTrackPoints(List<LatLng> points, bool toGcj02) {
    if (toGcj02) {
      return points.map((point) => wgs84ToGcj02(point)).toList();
    } else {
      return points.map((point) => gcj02ToWgs84(point)).toList();
    }
  }
} 