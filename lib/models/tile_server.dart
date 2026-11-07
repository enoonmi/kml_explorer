/// 一个瓦片地图供应商。
///
/// 用 [isChineseMap] 显式标注坐标系，取代原先靠名字里 `contains('高德')`
/// 判断的做法——新增国产底图只需置位该字段，不会再漏改。
class TileServer {
  const TileServer({
    required this.name,
    required this.url,
    required this.attribution,
    this.subdomains,
    this.isChineseMap = false,
    this.status = TileServerStatus.unknown,
    this.visible = true,
    this.errorMessage,
  });

  final String name;
  final String url;
  final String attribution;
  final List<String>? subdomains;

  /// 是否使用 GCJ-02 坐标系（高德、天地图等国内底图）。
  final bool isChineseMap;

  /// 最近一次探测的状态。
  final TileServerStatus status;

  /// 是否出现在供应商选择列表中。
  final bool visible;

  /// 最近一次探测失败的原因，仅用于诊断面板展示。
  final String? errorMessage;

  /// 天地图系列需要 API Key 才能出图。
  bool get requiresTiandituKey => url.contains('tianditu.gov.cn');

  TileServer copyWith({
    TileServerStatus? status,
    bool? visible,
    String? errorMessage,
  }) {
    return TileServer(
      name: name,
      url: url,
      attribution: attribution,
      subdomains: subdomains,
      isChineseMap: isChineseMap,
      status: status ?? this.status,
      visible: visible ?? this.visible,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

enum TileServerStatus { unknown, available, unavailable, testing }

/// 内置供应商清单。
const List<TileServer> kDefaultTileServers = [
  TileServer(
    name: 'OpenStreetMap',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
  ),
  TileServer(
    name: '高德地图',
    url:
        'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
    attribution: '© 高德地图',
    subdomains: ['1', '2', '3', '4'],
    isChineseMap: true,
  ),
  TileServer(
    name: '高德卫星',
    url: 'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
    attribution: '© 高德地图',
    subdomains: ['1', '2', '3', '4'],
    isChineseMap: true,
  ),
  TileServer(
    name: '天地图矢量',
    url:
        'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
    attribution: '© 天地图',
    subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
    isChineseMap: true,
  ),
  TileServer(
    name: '天地图影像',
    url:
        'https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
    attribution: '© 天地图',
    subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
    isChineseMap: true,
  ),
  TileServer(
    name: '天地图地形',
    url:
        'https://t{s}.tianditu.gov.cn/ter_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ter&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
    attribution: '© 天地图',
    subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
    isChineseMap: true,
  ),
  TileServer(
    name: 'CartoDB Positron',
    url:
        'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
    attribution: '© CartoDB',
    subdomains: ['a', 'b', 'c', 'd'],
  ),
  TileServer(
    name: 'CartoDB Dark Matter',
    url:
        'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
    attribution: '© CartoDB',
    subdomains: ['a', 'b', 'c', 'd'],
  ),
  TileServer(
    name: 'OpenTopoMap',
    url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    attribution: '© OpenTopoMap',
    subdomains: ['a', 'b', 'c'],
  ),
  TileServer(
    name: 'CyclOSM',
    url: 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    attribution: '© CyclOSM',
    subdomains: ['a', 'b', 'c'],
  ),
  TileServer(
    name: 'Esri World Imagery',
    url:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: '© Esri',
  ),
];
