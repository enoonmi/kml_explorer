import 'package:flutter_test/flutter_test.dart';
import 'package:kml_explorer/utils/coord_transform.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('CoordTransform', () {
    test('中国境内坐标应从 WGS-84 偏移到 GCJ-02', () {
      const wgs = LatLng(22.838094, 113.8045061); // 东莞长安
      final gcj = CoordTransform.wgs84ToGcj02(wgs);

      expect(gcj.latitude, isNot(equals(wgs.latitude)));
      expect(gcj.longitude, isNot(equals(wgs.longitude)));

      // 国内偏移量级为数百米
      final offset = const Distance().as(LengthUnit.Meter, wgs, gcj);
      expect(offset, greaterThan(50));
      expect(offset, lessThan(1000));
    });

    test('偏移方向应与中国境内 GCJ-02 的实际表现一致', () {
      // 广东一带：纬度向南偏、经度向东偏
      const wgs = LatLng(22.838094, 113.8045061);
      final gcj = CoordTransform.wgs84ToGcj02(wgs);

      expect(gcj.latitude, lessThan(wgs.latitude));
      expect(gcj.longitude, greaterThan(wgs.longitude));
    });

    test('境外坐标应原样返回', () {
      const tokyo = LatLng(35.681236, 139.767125);
      final result = CoordTransform.wgs84ToGcj02(tokyo);
      expect(result.latitude, tokyo.latitude);
      expect(result.longitude, tokyo.longitude);
    });

    test('WGS-84 → GCJ-02 → WGS-84 往返误差应在米级以内', () {
      const origin = LatLng(22.838094, 113.8045061);
      final roundTrip = CoordTransform.gcj02ToWgs84(
        CoordTransform.wgs84ToGcj02(origin),
      );
      final error = const Distance().as(LengthUnit.Meter, origin, roundTrip);
      // 算法是近似逆变换，实测约 2 米，属可接受范围
      expect(error, lessThan(5));
    });

    test('批量转换应保持顺序与数量', () {
      const points = [
        LatLng(22.83, 113.80),
        LatLng(22.84, 113.81),
        LatLng(22.85, 113.82),
      ];
      final converted = CoordTransform.transformTrackPoints(points, true);

      expect(converted, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        final moved = const Distance().as(LengthUnit.Meter, points[i], converted[i]);
        expect(moved, greaterThan(0), reason: '第 $i 个点应发生偏移');
      }
    });

    test('toGcj02 为 false 时应执行反向转换', () {
      const gcj = LatLng(22.835245, 113.8096);
      final back = CoordTransform.transformTrackPoints([gcj], false).single;
      // 反向转换后纬度应回北、经度回西
      expect(back.latitude, greaterThan(gcj.latitude));
      expect(back.longitude, lessThan(gcj.longitude));
    });
  });
}
