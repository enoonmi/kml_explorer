import 'package:flutter_test/flutter_test.dart';
import 'package:kml_explorer/models/kml_parser.dart';

void main() {
  group('KmlParser', () {
    test('解析 gx:Track 时应读取真实时间戳', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>测试轨迹</name>
    <Placemark>
      <gx:Track>
        <when>2025-06-02T02:28:03Z</when>
        <when>2025-06-02T02:28:33Z</when>
        <gx:coord>113.8045061 22.838094 63.5</gx:coord>
        <gx:coord>113.8045161 22.838104 63.6</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>
''';
      final result = KmlParser.parseKmlFile(kml);
      final points = result['points'] as List<TrackPoint>;

      expect(points, hasLength(2));
      expect(result['name'], '测试轨迹');
      // 坐标顺序应为 KML 的 lng lat alt → lat lng
      expect(points.first.latitude, closeTo(22.838094, 1e-6));
      expect(points.first.longitude, closeTo(113.8045061, 1e-6));
      expect(points.first.altitude, closeTo(63.5, 1e-6));
      expect(
        points.last.timestamp.difference(points.first.timestamp).inSeconds,
        30,
      );
    });

    test('解析 LineString 时应按 30 秒步长合成时间戳', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <TimeStamp><when>2025-01-01T00:00:00Z</when></TimeStamp>
      <LineString>
        <coordinates>113.0,22.0,10 113.1,22.1,20 113.2,22.2,30</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
''';
      final result = KmlParser.parseKmlFile(kml);
      final points = result['points'] as List<TrackPoint>;

      expect(points, hasLength(3));
      expect(
        points[1].timestamp.difference(points[0].timestamp).inSeconds,
        30,
      );
      expect(
        points[2].timestamp.difference(points[0].timestamp).inSeconds,
        60,
      );
    });

    test('应从 ExtendedData 读取 TrackTags 并剥离 CDATA', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <ExtendedData>
      <Data name="TrackTags"><value><![CDATA[爬山,徒步]]></value></Data>
    </ExtendedData>
  </Document>
</kml>
''';
      final result = KmlParser.parseKmlFile(kml);
      expect(result['tags'], ['爬山', '徒步']);
    });

    test('标注点文件夹中的 Point 应解析为 marker 而非轨迹点', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Folder>
      <name>标注点</name>
      <Placemark id="startPoint">
        <name>起点</name>
        <Point><coordinates>113.8045061,22.838094,63.5</coordinates></Point>
      </Placemark>
    </Folder>
  </Document>
</kml>
''';
      final result = KmlParser.parseKmlFile(kml);
      final markers = result['markers'] as List;

      expect(markers, hasLength(1));
      expect((result['points'] as List), isEmpty);
      expect(markers.first.name, '起点');
    });

    test('KML 颜色 AABBGGRR 应正确映射为 ARGB', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Style id="LineStringStyle">
      <LineStyle><color>ff1034e8</color><width>6</width></LineStyle>
    </Style>
  </Document>
</kml>
''';
      final result = KmlParser.parseKmlFile(kml);
      // ff1034e8 => a=ff, b=10, g=34, r=e8
      expect((result['trackColor'] as dynamic).toARGB32(), 0xFFE83410);
      expect(result['trackWidth'], 6.0);
    });

    test('内容为空时不应抛异常', () {
      final result = KmlParser.parseKmlFile('not xml at all');
      expect((result['points'] as List), isEmpty);
      expect((result['markers'] as List), isEmpty);
    });
  });
}
