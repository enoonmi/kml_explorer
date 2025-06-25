import 'dart:async';
import 'dart:io';
import 'dart:math' show min, max, log;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/kml_file.dart';
import 'models/kml_marker.dart';
import 'models/map_config.dart';
import 'pages/file_manager_page.dart';
import 'pages/marker_info_dialog.dart';
import 'pages/webdav_settings_page.dart';
import 'services/permission_service.dart';
import 'services/webdav_service.dart';
import 'utils/coord_transform.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KML Explorer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}

// 瓦片服务器状态枚举
enum TileServerStatus {
  unknown,
  available,
  unavailable,
  testing,
}

// 瓦片服务器数据类
class TileServer {
  final String name;
  final String url;
  final String attribution;
  final List<String>? subdomains;
  TileServerStatus status;
  String? errorMessage;
  bool visible; // 新增：控制是否在选择界面中显示

  TileServer({
    required this.name,
    required this.url,
    required this.attribution,
    this.subdomains,
    this.status = TileServerStatus.unknown,
    this.errorMessage,
    this.visible = true, // 默认可见
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'attribution': attribution,
      'subdomains': subdomains,
      'status': status.index,
      'errorMessage': errorMessage,
      'visible': visible,
    };
  }

  factory TileServer.fromJson(Map<String, dynamic> json) {
    return TileServer(
      name: json['name'],
      url: json['url'],
      attribution: json['attribution'],
      subdomains: json['subdomains'] != null 
          ? List<String>.from(json['subdomains'])
          : null,
      status: TileServerStatus.values[json['status'] ?? 0],
      errorMessage: json['errorMessage'],
      visible: json['visible'] ?? true,
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  List<KmlFile> _kmlFiles = [];
  List<KmlFile> _filteredFiles = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _isLoading = false;
  bool _mapLoaded = false;
  String _mapError = '';
  String _networkStatus = '检查中...';
  bool _mapControllerReady = false;
  int _currentTileServerIndex = 0;
  bool _showFileManager = true;
  LatLng? _currentLocation;
  bool _isLocationLoading = false;

  // 瓦片服务器列表
  List<TileServer> _tileServers = [];

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 初始化WebDAV服务
    await WebDavService.instance.initialize();
    
    debugPrint('MapPage: initState 开始');
    _initializeTileServers();
    
    // 先加载设置，确保地图供应商选择正确
    await _loadSettings();
    
    _loadKmlFiles();
    _getCurrentLocation();
    // 加载天地图API密钥
    MapConfig.loadTiandituApiKey();
    
    // 延迟网络检查和瓦片服务器测试
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _checkNetworkAndLoadMap();
        // 进一步延迟瓦片服务器测试，避免影响应用启动
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) {
            _testAllTileServers();
          }
        });
      }
    });
    debugPrint('MapPage: initState 完成');
  }

  // 初始化瓦片服务器列表
  void _initializeTileServers() {
    _tileServers = [
      TileServer(
        name: 'OpenStreetMap',
        url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        attribution: '© OpenStreetMap contributors',
      ),
      TileServer(
        name: '高德地图',
        url: 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
        attribution: '© 高德地图',
        subdomains: ['1', '2', '3', '4'],
      ),
      TileServer(
        name: '高德卫星',
        url: 'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
        attribution: '© 高德地图',
        subdomains: ['1', '2', '3', '4'],
      ),
      TileServer(
        name: '天地图矢量',
        url: 'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
        attribution: '© 天地图',
        subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
      ),
      TileServer(
        name: '天地图影像',
        url: 'https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
        attribution: '© 天地图',
        subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
      ),
      TileServer(
        name: '天地图地形',
        url: 'https://t{s}.tianditu.gov.cn/ter_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ter&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=你的天地图密钥',
        attribution: '© 天地图',
        subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
      ),
      TileServer(
        name: 'CartoDB Positron',
        url: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
        attribution: '© CartoDB',
        subdomains: ['a', 'b', 'c', 'd'],
      ),
      TileServer(
        name: 'CartoDB Dark Matter',
        url: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
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
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        attribution: '© Esri',
      ),
      TileServer(
        name: 'Stamen Terrain',
        url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/terrain/{z}/{x}/{y}.png',
        attribution: '© Stamen Design',
        subdomains: ['a', 'b', 'c', 'd'],
      ),
      TileServer(
        name: 'Stamen Watercolor',
        url: 'https://stamen-tiles-{s}.a.ssl.fastly.net/watercolor/{z}/{x}/{y}.png',
        attribution: '© Stamen Design',
        subdomains: ['a', 'b', 'c', 'd'],
      ),
    ];
    
    // 确保所有瓦片服务器默认可见
    for (var server in _tileServers) {
      server.visible = true;
    }
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTileServerIndex = prefs.getInt('tile_server_index');
      
      // 检查是否是初次使用（通过检查是否有任何可见性设置来判断）
      bool isFirstTime = true;
      for (int i = 0; i < _tileServers.length; i++) {
        if (prefs.containsKey('tile_server_visible_$i')) {
          isFirstTime = false;
          break;
        }
      }
      
      // 加载瓦片服务器可见性设置
      for (int i = 0; i < _tileServers.length; i++) {
        if (isFirstTime) {
          // 初次使用，默认所有服务器都可见
          _tileServers[i].visible = true;
          // 保存默认设置
          await prefs.setBool('tile_server_visible_$i', true);
        } else {
          // 非初次使用，加载保存的设置
          final visible = prefs.getBool('tile_server_visible_$i');
          if (visible != null) {
            _tileServers[i].visible = visible;
          } else {
            // 如果某个设置不存在，默认可见
            _tileServers[i].visible = true;
            await prefs.setBool('tile_server_visible_$i', true);
          }
        }
      }
      
      // 加载用户选择的地图供应商
      if (savedTileServerIndex != null && 
          savedTileServerIndex >= 0 && 
          savedTileServerIndex < _tileServers.length) {
        setState(() {
          _currentTileServerIndex = savedTileServerIndex;
        });
        debugPrint('加载用户选择的地图供应商: ${_tileServers[savedTileServerIndex].name}');
        
        // 显示用户选择的地图供应商信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已加载地图供应商: ${_tileServers[savedTileServerIndex].name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 如果没有保存的选择，默认使用第一个可见的服务器
        final firstVisibleIndex = _tileServers.indexWhere((server) => server.visible);
        if (firstVisibleIndex != -1) {
          setState(() {
            _currentTileServerIndex = firstVisibleIndex;
          });
          debugPrint('使用默认地图供应商: ${_tileServers[firstVisibleIndex].name}');
        }
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
      // 如果加载失败，确保所有服务器都可见，并选择第一个
      for (int i = 0; i < _tileServers.length; i++) {
        _tileServers[i].visible = true;
      }
      setState(() {
        _currentTileServerIndex = 0;
      });
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tile_server_index', _currentTileServerIndex);
      
      // 保存瓦片服务器可见性设置
      for (int i = 0; i < _tileServers.length; i++) {
        await prefs.setBool('tile_server_visible_$i', _tileServers[i].visible);
      }
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  // 获取当前位置
  Future<void> _getCurrentLocation() async {
    if (_isLocationLoading) return;
    
    setState(() {
      _isLocationLoading = true;
    });

    try {
      // 检查位置权限
      final permission = await PermissionService().requestLocationPermission(context);
      if (!permission) {
        debugPrint('位置权限被拒绝');
        setState(() {
          _isLocationLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        // 根据当前地图类型进行坐标转换
        final currentServer = _tileServers[_currentTileServerIndex];
        final isChineseMap = currentServer.name.contains('高德') || currentServer.name.contains('天地图');
        
        LatLng transformedLocation;
        if (isChineseMap) {
          // 国内地图需要转换为GCJ-02坐标系
          transformedLocation = CoordTransform.wgs84ToGcj02(LatLng(position.latitude, position.longitude));
        } else {
          // 国外地图使用WGS-84坐标系，无需转换
          transformedLocation = LatLng(position.latitude, position.longitude);
        }
        
        setState(() {
          _currentLocation = transformedLocation;
          _isLocationLoading = false;
        });

        // 如果地图已加载，移动到当前位置
        if (_mapControllerReady) {
          _mapController.move(_currentLocation!, 15.0);
        }

        debugPrint('当前位置: ${position.latitude}, ${position.longitude}');
        debugPrint('转换后位置: ${transformedLocation.latitude}, ${transformedLocation.longitude}');
      }
    } catch (e) {
      debugPrint('获取位置失败: $e');
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }
    }
  }

  // 测试所有瓦片服务器
  Future<void> _testAllTileServers() async {
    if (!mounted) return;

    debugPrint('开始测试瓦片服务器...');
    
    // 测试所有可见的瓦片服务器
    final visibleServers = _tileServers.where((server) => server.visible).toList();
    
    for (int i = 0; i < visibleServers.length; i++) {
      if (!mounted) return;
      
      final server = visibleServers[i];
      final serverIndex = _tileServers.indexOf(server);
      
      setState(() {
        _tileServers[serverIndex].status = TileServerStatus.testing;
      });

      try {
        final isAvailable = await _testTileServer(_tileServers[serverIndex]);
        
        if (mounted) {
          setState(() {
            _tileServers[serverIndex].status = isAvailable 
                ? TileServerStatus.available 
                : TileServerStatus.unavailable;
          });
        }
      } catch (e) {
        debugPrint('测试瓦片服务器失败: $e');
        if (mounted) {
          setState(() {
            _tileServers[serverIndex].status = TileServerStatus.unavailable;
          });
        }
      }

      // 延迟一下，避免同时发起太多请求
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 自动选择逻辑：只在当前选择的地图供应商不可用时才切换
    if (mounted) {
      final currentServer = _tileServers[_currentTileServerIndex];
      
      // 检查当前选择的地图供应商是否可用
      if (currentServer.status == TileServerStatus.unavailable && currentServer.visible) {
        // 当前选择的地图供应商不可用，寻找第一个可用的服务器
        final availableIndex = _tileServers.indexWhere(
          (server) => server.status == TileServerStatus.available && server.visible
        );
        if (availableIndex != -1) {
          setState(() {
            _currentTileServerIndex = availableIndex;
          });
          _saveSettings();
          debugPrint('当前地图供应商不可用，自动切换到: ${_tileServers[availableIndex].name}');
        }
      } else if (currentServer.status == TileServerStatus.available) {
        // 当前选择的地图供应商可用，保持用户的选择
        debugPrint('保持用户选择的地图供应商: ${currentServer.name}');
      }
    }
    
    debugPrint('瓦片服务器测试完成');
  }

  // 测试单个瓦片服务器
  Future<bool> _testTileServer(TileServer server) async {
    try {
      String testUrl = server.url;
      
      // 替换URL中的占位符
      testUrl = testUrl
          .replaceAll('{z}', '10')
          .replaceAll('{x}', '512')
          .replaceAll('{y}', '256');
      
      if (server.subdomains != null && server.subdomains!.isNotEmpty) {
        testUrl = testUrl.replaceAll('{s}', server.subdomains!.first);
      }

      final response = await http.get(
        Uri.parse(testUrl),
        headers: {
          'User-Agent': 'KML Explorer/1.0',
          'Accept': 'image/png,image/*,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      server.errorMessage = e.toString();
      debugPrint('瓦片服务器测试失败 ${server.name}: $e');
      return false;
    }
  }

  Future<void> _checkNetworkAndLoadMap() async {
    if (!mounted) return;
    
    setState(() {
      _networkStatus = '检查网络连接...';
    });

    try {
      final response = await http.get(
        Uri.parse('https://httpbin.org/get'),
        headers: {'User-Agent': 'KML Explorer/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _networkStatus = '网络连接正常';
          _mapLoaded = true;
          _mapError = '';
        });
        debugPrint('网络连接正常，地图已启用');
      } else {
        setState(() {
          _networkStatus = '网络连接异常: ${response.statusCode}';
          _mapLoaded = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _networkStatus = '网络连接失败: $e';
        _mapLoaded = true;
      });
      debugPrint('网络测试失败: $e');
    }
  }

  void _selectTileServer(int index) {
    if (index >= 0 && index < _tileServers.length) {
      final previousServer = _tileServers[_currentTileServerIndex];
      final newServer = _tileServers[index];
      
      setState(() {
        _currentTileServerIndex = index;
      });
      _saveSettings();
      
      debugPrint('选择瓦片服务器: ${newServer.name}');
      
      // 显示选择反馈
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已切换到: ${newServer.name}'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                setState(() {
                  _currentTileServerIndex = _tileServers.indexOf(previousServer);
                });
                _saveSettings();
                _updatePolylines();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已恢复到: ${previousServer.name}')),
                );
              },
            ),
          ),
        );
      }
      
      // 切换地图供应商后重新更新轨迹显示，应用坐标转换
      _updatePolylines();
    }
  }

  // 显示瓦片服务器选择器
  void _showTileServerSelector() {
    // 只显示可见的瓦片服务器
    final visibleServers = _tileServers.where((server) => server.visible).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择地图供应商'),
        content: SizedBox(
          width: 500, // 控制界面宽度
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: visibleServers.length,
            itemBuilder: (context, index) {
              final server = visibleServers[index];
              final serverIndex = _tileServers.indexOf(server);
              return ListTile(
                leading: _buildStatusIcon(server.status),
                title: Text(server.name),
                subtitle: Text(server.attribution),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 天地图选项添加设置按钮
                    if (server.name.contains('天地图'))
                      IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showTiandituSettings();
                        },
                        tooltip: '天地图设置',
                      ),
                    if (_currentTileServerIndex == serverIndex)
                      const Icon(Icons.check, color: Colors.blue),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectTileServer(serverIndex);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showTileServerSettings();
            },
            child: const Text('设置'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _testAllTileServers();
            },
            child: const Text('重新测试'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 显示天地图设置对话框
  void _showTiandituSettings() {
    final controller = TextEditingController(text: MapConfig.tiandituApiKey);
    bool isLoading = false;
    bool isKeyValid = MapConfig.isTiandituKeyValid;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('天地图API密钥设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('密钥状态: '),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isKeyValid ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isKeyValid ? '已配置' : '未配置',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '天地图需要API密钥才能正常使用。请访问天地图官网申请密钥：',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'https://www.tianditu.gov.cn/',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API密钥',
                  hintText: '请输入天地图API密钥',
                  border: OutlineInputBorder(),
                  helperText: '密钥格式：xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                ),
                obscureText: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: isLoading ? null : () async {
                setState(() {
                  isLoading = true;
                });

                try {
                  await MapConfig.setTiandituApiKey(controller.text.trim());
                  setState(() {
                    isKeyValid = MapConfig.isTiandituKeyValid;
                    isLoading = false;
                  });
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('天地图API密钥已保存')),
                    );
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  setState(() {
                    isLoading = false;
                  });
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('保存失败: $e')),
                    );
                  }
                }
              },
              child: isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // 显示瓦片服务器设置界面
  void _showTileServerSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('地图供应商设置'),
          content: SizedBox(
            width: 500, // 控制界面宽度
            height: 400,
            child: Column(
              children: [
                const Text(
                  '选择要在地图供应商选择界面中显示的地图服务：',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tileServers.length,
                    itemBuilder: (context, index) {
                      final server = _tileServers[index];
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(server.name)),
                            if (server.name.contains('天地图'))
                              IconButton(
                                icon: const Icon(Icons.settings, size: 16),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _showTiandituSettings();
                                },
                                tooltip: '天地图设置',
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(server.attribution, style: const TextStyle(fontSize: 12)),
                            Row(
                              children: [
                                _buildStatusIcon(server.status),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusText(server.status),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        value: server.visible,
                        onChanged: (bool? value) {
                          setState(() {
                            server.visible = value ?? true;
                          });
                        },
                        secondary: IconButton(
                          icon: const Icon(Icons.refresh, size: 16),
                          onPressed: () async {
                            setState(() {
                              server.status = TileServerStatus.testing;
                            });
                            
                            try {
                              final isAvailable = await _testTileServer(server);
                              setState(() {
                                server.status = isAvailable 
                                    ? TileServerStatus.available 
                                    : TileServerStatus.unavailable;
                              });
                            } catch (e) {
                              setState(() {
                                server.status = TileServerStatus.unavailable;
                              });
                            }
                          },
                          tooltip: '测试连接',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 重置所有设置为默认值
                setState(() {
                  for (var server in _tileServers) {
                    server.visible = true;
                  }
                });
              },
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testAllTileServers();
              },
              child: const Text('测试全部'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveSettings();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置已保存')),
                );
              },
              child: const Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  // 构建状态图标
  Widget _buildStatusIcon(TileServerStatus status) {
    switch (status) {
      case TileServerStatus.available:
        return Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        );
      case TileServerStatus.unavailable:
        return Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        );
      case TileServerStatus.testing:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TileServerStatus.unknown:
        return Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Colors.grey,
            shape: BoxShape.circle,
          ),
        );
    }
  }

  Future<void> _loadKmlFiles() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await KmlFileManager.loadKmlFiles();
      if (!mounted) return;
      
      setState(() {
        _kmlFiles = files;
        _isLoading = false;
      });
      _updatePolylines();
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载文件列表失败: $e')),
      );
    }
  }

  void _updatePolylines() {
    final visibleFiles = _kmlFiles.where((file) => file.isVisible).toList();
    final polylines = <Polyline>[];
    final markers = <Marker>[];
    
    // 判断当前地图是否为国内地图（需要坐标转换）
    final currentServer = _tileServers[_currentTileServerIndex];
    final isChineseMap = currentServer.name.contains('高德') || currentServer.name.contains('天地图');
    
    for (final file in visibleFiles) {
      if (file.visiblePoints.isNotEmpty) {
        // 根据地图类型获取转换后的轨迹点
        final transformedPoints = file.getVisiblePointsForMap(isChineseMap);
        
        polylines.add(
          Polyline(
            points: transformedPoints,
            color: file.trackColor,
            strokeWidth: file.trackWidth,
          ),
        );
      }
      
      // 添加标记点
      final transformedMarkers = file.getMarkersForMap(isChineseMap);
      for (final marker in transformedMarkers) {
        // 检查是否为起点或终点标记
        final isStartOrEndPoint = marker.name == '起点' || marker.name == '终点';
        final hasImage = marker.imageUrl != null || marker.imageFileName != null;
        
        markers.add(
          Marker(
            point: marker.position,
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showMarkerInfo(marker),
              child: Container(
                decoration: BoxDecoration(
                  color: hasImage 
                      ? Colors.red 
                      : (isStartOrEndPoint ? Colors.green : Colors.blue),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(red: 0, green: 0, blue: 0, alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  hasImage 
                      ? Icons.photo_camera 
                      : (isStartOrEndPoint ? Icons.play_arrow : Icons.location_on),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        );
      }
    }
    
    setState(() {
      _polylines = polylines;
      _markers = markers;
    });

    // 只有在没有手动跳转到特定轨迹时才自动调整地图视图
    // 这里移除自动调整，避免干扰用户的手动操作
  }

  // 显示标记点信息
  void _showMarkerInfo(KmlMarker marker) {
    showDialog(
      context: context,
      builder: (context) => MarkerInfoDialog(marker: marker),
    ).then((result) {
      if (!mounted) return;
      if (result == 'navigate') {
        // 导航到此位置
        _mapController.move(marker.position, 15.0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导航到标记点: ${marker.name.isNotEmpty ? marker.name : '图片标记点'}')),
        );
      }
    });
  }

  // 跳转到指定轨迹
  void _jumpToTrack(KmlFile file) {
    if (file.visiblePoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该轨迹没有可显示的点')),
      );
      return;
    }

    try {
      // 判断当前地图是否为国内地图（需要坐标转换）
      final currentServer = _tileServers[_currentTileServerIndex];
      final isChineseMap = currentServer.name.contains('高德') || currentServer.name.contains('天地图');
      
      // 获取转换后的轨迹点
      final transformedPoints = file.getVisiblePointsForMap(isChineseMap);
      
      // 使用转换后的点计算边界
      double minLat = 90.0, maxLat = -90.0;
      double minLng = 180.0, maxLng = -180.0;
      
      for (var point in transformedPoints) {
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }
      
      // 添加边距
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final latPadding = latSpan * 0.15;
      final lngPadding = lngSpan * 0.15;
      
      final bounds = {
        'minLat': minLat - latPadding,
        'maxLat': maxLat + latPadding,
        'minLng': minLng - lngPadding,
        'maxLng': maxLng + lngPadding,
      };
      
      final center = LatLng(
        (bounds['minLat']! + bounds['maxLat']!) / 2,
        (bounds['minLng']! + bounds['maxLng']!) / 2,
      );

      // 使用新的缩放计算方法
      final zoom = file.optimalZoom;

      debugPrint('跳转到轨迹: ${file.displayName}');
      debugPrint('地图类型: ${isChineseMap ? "国内地图" : "国外地图"}');
      debugPrint('边界: $bounds');
      debugPrint('中心点: $center');
      debugPrint('缩放级别: $zoom');

      _mapController.move(center, zoom);
      
      // 高亮显示选中的轨迹
      setState(() {
        _polylines = _polylines.map((polyline) {
          if (polyline.points == transformedPoints) {
            return Polyline(
              points: polyline.points,
              color: polyline.color,
              strokeWidth: polyline.strokeWidth + 2, // 加粗显示
            );
          }
          return polyline;
        }).toList();
      });

      // 5秒后恢复正常显示，但不重新调整地图位置
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _polylines = _polylines.map((polyline) {
              if (polyline.points == transformedPoints) {
                return Polyline(
                  points: polyline.points,
                  color: polyline.color,
                  strokeWidth: polyline.strokeWidth - 2, // 恢复正常粗细
                );
              }
              return polyline;
            }).toList();
          });
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已跳转到轨迹: ${file.displayName}')),
      );
    } catch (e) {
      debugPrint('跳转到轨迹失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('跳转到轨迹失败')),
      );
    }
  }

  // 调整地图视图以适应所有轨迹（仅在需要时调用）
  void _fitMapToAllPolylines() {
    try {
      if (_polylines.isEmpty) return;

      // 计算所有轨迹的边界
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      
      for (var polyline in _polylines) {
        for (var point in polyline.points) {
          minLat = min(minLat, point.latitude);
          maxLat = max(maxLat, point.latitude);
          minLng = min(minLng, point.longitude);
          maxLng = max(maxLng, point.longitude);
        }
      }

      final center = LatLng(
        (minLat + maxLat) / 2,
        (minLng + maxLng) / 2,
      );

      // 使用改进的缩放计算
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final maxSpan = max(latSpan, lngSpan);
      
      double zoom = 15.0;
      if (maxSpan > 0) {
        // 使用与单个轨迹相同的缩放计算公式
        const double earthCircumference = 40075016.686;
        zoom = log(earthCircumference / (maxSpan * 111320)) / log(2);
        zoom = zoom - 0.3; // 稍微缩小一点，为所有轨迹留出空间
        zoom = zoom.clamp(3.0, 18.0);
      }

      debugPrint('调整到所有轨迹视图');
      debugPrint('边界: minLat=$minLat, maxLat=$maxLat, minLng=$minLng, maxLng=$maxLng');
      debugPrint('中心点: $center');
      debugPrint('缩放级别: $zoom');

      _mapController.move(center, zoom);
    } catch (e) {
      debugPrint('调整地图视图失败: $e');
    }
  }

  // 调整地图视图以适应筛选的轨迹
  void _fitMapToFilteredPolylines(List<KmlFile> files) {
    try {
      if (files.isEmpty) return;

      // 判断当前地图是否为国内地图（需要坐标转换）
      final currentServer = _tileServers[_currentTileServerIndex];
      final isChineseMap = currentServer.name.contains('高德') || currentServer.name.contains('天地图');

      // 计算筛选轨迹的边界（使用转换后的坐标）
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      
      for (var file in files) {
        if (file.visiblePoints.isNotEmpty) {
          final transformedPoints = file.getVisiblePointsForMap(isChineseMap);
          for (var point in transformedPoints) {
            minLat = min(minLat, point.latitude);
            maxLat = max(maxLat, point.latitude);
            minLng = min(minLng, point.longitude);
            maxLng = max(maxLng, point.longitude);
          }
        }
      }

      final center = LatLng(
        (minLat + maxLat) / 2,
        (minLng + maxLng) / 2,
      );

      // 使用改进的缩放计算
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final maxSpan = max(latSpan, lngSpan);
      
      double zoom = 15.0;
      if (maxSpan > 0) {
        // 使用与单个轨迹相同的缩放计算公式
        const double earthCircumference = 40075016.686;
        zoom = log(earthCircumference / (maxSpan * 111320)) / log(2);
        zoom = zoom - 0.3; // 稍微缩小一点，为轨迹留出空间
        zoom = zoom.clamp(3.0, 18.0);
      }

      debugPrint('调整到筛选轨迹视图');
      debugPrint('地图类型: ${isChineseMap ? "国内地图" : "国外地图"}');
      debugPrint('文件数量: ${files.length}');
      debugPrint('边界: minLat=$minLat, maxLat=$maxLat, minLng=$minLng, maxLng=$maxLng');
      debugPrint('中心点: $center');
      debugPrint('缩放级别: $zoom');

      _mapController.move(center, zoom);
    } catch (e) {
      debugPrint('调整筛选轨迹视图失败: $e');
    }
  }

  void _onFilesChanged(List<KmlFile> files) {
    setState(() {
      _kmlFiles = files;
    });
    _updatePolylines();
  }

  void _onFilteredFilesChanged(List<KmlFile> filteredFiles) {
    setState(() {
      _filteredFiles = filteredFiles;
    });
  }

  Future<void> _importKmlFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kml'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        await KmlFileManager.saveKmlFile(file);
        await _loadKmlFiles();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件导入成功')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入文件时出错: $e')),
        );
      }
    }
  }

  void _showDiagnosticInfo() {
    String zoomInfo = '未初始化';
    String centerInfo = '未初始化';
    
    try {
      if (_mapControllerReady) {
        zoomInfo = _mapController.camera.zoom.toStringAsFixed(2);
        centerInfo = '${_mapController.camera.center.latitude.toStringAsFixed(4)}, ${_mapController.camera.center.longitude.toStringAsFixed(4)}';
      }
    } catch (e) {
      zoomInfo = '获取失败: $e';
      centerInfo = '获取失败: $e';
    }

    final currentServer = _tileServers[_currentTileServerIndex];
    final availableCount = _tileServers.where((s) => s.status == TileServerStatus.available).length;
    final visibleCount = _tileServers.where((s) => s.visible).length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('网络状态: $_networkStatus'),
              const SizedBox(height: 8),
              Text('地图加载: ${_mapLoaded ? "成功" : "失败"}'),
              Text('地图控制器: ${_mapControllerReady ? "就绪" : "未就绪"}'),
              Text('当前瓦片服务器: ${currentServer.name}'),
              Text('服务器状态: ${_getStatusText(currentServer.status)}'),
              Text('可用服务器数: $availableCount/${_tileServers.length}'),
              Text('可见服务器数: $visibleCount/${_tileServers.length}'),
              if (currentServer.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text('错误信息: ${currentServer.errorMessage}'),
              ],
              const SizedBox(height: 8),
              Text('当前缩放级别: $zoomInfo'),
              Text('当前中心点: $centerInfo'),
              if (_currentLocation != null) ...[
                Text('当前位置: ${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}'),
              ],
              const SizedBox(height: 8),
              Text('已加载文件数: ${_kmlFiles.length}'),
              Text('可见轨迹数: ${_polylines.length}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _testAllTileServers();
            },
            child: const Text('重新测试'),
          ),
        ],
      ),
    );
  }

  String _getStatusText(TileServerStatus status) {
    switch (status) {
      case TileServerStatus.available:
        return '可用';
      case TileServerStatus.unavailable:
        return '不可用';
      case TileServerStatus.testing:
        return '测试中';
      case TileServerStatus.unknown:
        return '未知';
    }
  }

  Widget _buildTileLayer(TileServer tileServer) {
    // 动态获取URL，处理天地图密钥
    final urlTemplate = tileServer.name.contains('天地图') 
        ? MapConfig.getTiandituUrl(tileServer.url)
        : tileServer.url;
    
    if (tileServer.subdomains != null) {
      return TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: 'com.example.kml_explorer',
        maxZoom: 18,
        minZoom: 3,
        keepBuffer: 2,
        tms: false,
        subdomains: tileServer.subdomains!,
        fallbackUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
    } else {
      return TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: 'com.example.kml_explorer',
        maxZoom: 18,
        minZoom: 3,
        keepBuffer: 2,
        tms: false,
        fallbackUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
    }
  }

  // 显示应用信息
  void _showAppInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('应用信息'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KML Explorer v1.0'),
            SizedBox(height: 8),
            Text('一个用于管理和查看KML轨迹文件的应用'),
            SizedBox(height: 8),
            Text('支持多种地图供应商和轨迹编辑功能'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 显示WebDAV设置
  void _showWebDavSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const WebDavSettingsPage(),
      ),
    );
  }

  // 显示移动端文件管理
  void _showMobileFileManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('文件管理'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: FileManagerPage(
            onFilesChanged: _onFilesChanged,
            onTrackSelected: (file) {
              Navigator.of(context).pop();
              _jumpToTrack(file);
            },
            onFilteredFilesChanged: _onFilteredFilesChanged,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTileServer = _tileServers[_currentTileServerIndex];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('KML Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              debugPrint('设置按钮被点击');
              try {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('设置'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.info),
                          title: const Text('应用信息'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showAppInfo();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.bug_report),
                          title: const Text('诊断信息'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showDiagnosticInfo();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.cloud),
                          title: const Text('WebDAV设置'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showWebDavSettings();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.map),
                          title: const Text('地图供应商设置'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showTileServerSettings();
                          },
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                );
                debugPrint('设置对话框显示成功');
              } catch (e) {
                debugPrint('设置对话框显示失败: $e');
              }
            },
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: _showTileServerSelector,
            tooltip: '选择地图供应商 (${currentTileServer.name})',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importKmlFile,
            tooltip: '导入 KML 文件',
          ),
          // 移动端文件管理按钮
          if (!_isDesktop)
            IconButton(
              icon: const Icon(Icons.folder),
              onPressed: _showMobileFileManager,
              tooltip: '文件管理',
            ),
          if (_isDesktop)
            IconButton(
              icon: Icon(_showFileManager ? Icons.chevron_left : Icons.menu),
              tooltip: _showFileManager ? '隐藏文件管理' : '显示文件管理',
              onPressed: () {
                setState(() {
                  _showFileManager = !_showFileManager;
                });
              },
            ),
        ],
      ),
      body: Row(
        children: [
          if (_isDesktop)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _showFileManager
                  ? SizedBox(
                      key: const ValueKey('fileManager'),
                      width: 320,
                      child: FileManagerPage(
                        onFilesChanged: _onFilesChanged,
                        onTrackSelected: _jumpToTrack,
                        onFilteredFilesChanged: _onFilteredFilesChanged,
                      ),
                    )
                  : const SizedBox(width: 0, key: ValueKey('empty')),
            ),
          // 地图区域
          Expanded(
            child: Stack(
              children: [
                // 地图容器
                Container(
                  color: Colors.grey[200],
                  child: _mapLoaded 
                    ? FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentLocation ?? LatLng(39.9042, 116.4074),
                          initialZoom: _currentLocation != null ? 15.0 : 10.0,
                          interactionOptions: const InteractionOptions(
                            enableMultiFingerGestureRace: true,
                          ),
                          onMapReady: () {
                            debugPrint('地图已准备就绪');
                            setState(() {
                              _mapLoaded = true;
                              _mapControllerReady = true;
                            });
                            // 如果有轨迹，调整视图
                            if (_polylines.isNotEmpty) {
                              _fitMapToAllPolylines();
                            }
                          },
                        ),
                        children: [
                          _buildTileLayer(currentTileServer),
                          PolylineLayer(
                            polylines: _polylines,
                          ),
                          // 标记点层
                          MarkerLayer(
                            markers: _markers,
                          ),
                          // 当前位置标记
                          if (_currentLocation != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _currentLocation!,
                                  width: 20,
                                  height: 20,
                                  child: const Icon(
                                    Icons.my_location,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.map, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('地图加载中...', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(_networkStatus, style: Theme.of(context).textTheme.bodyMedium),
                            if (_mapError.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_mapError, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
                            ],
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _checkNetworkAndLoadMap,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                ),
                // 导航控制按钮
                if (_mapLoaded && _mapControllerReady) ...[
                  Positioned(
                    right: 16,
                    top: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          onPressed: () {
                            try {
                              final currentZoom = _mapController.camera.zoom;
                              _mapController.move(_mapController.camera.center, currentZoom + 1);
                            } catch (e) {
                              debugPrint('缩放操作失败: $e');
                            }
                          },
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          onPressed: () {
                            try {
                              final currentZoom = _mapController.camera.zoom;
                              _mapController.move(_mapController.camera.center, currentZoom - 1);
                            } catch (e) {
                              debugPrint('缩放操作失败: $e');
                            }
                          },
                          child: const Icon(Icons.remove),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          onPressed: () {
                            // 使用当前筛选的文件列表
                            final filesToShow = _filteredFiles.isNotEmpty ? _filteredFiles : _kmlFiles;
                            final visibleFiles = filesToShow.where((file) => file.isVisible).toList();
                            
                            if (visibleFiles.isNotEmpty) {
                              _fitMapToFilteredPolylines(visibleFiles);
                              final categoryText = _filteredFiles.isNotEmpty && _filteredFiles.length < _kmlFiles.length 
                                  ? '当前分类' 
                                  : '所有';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已调整到$categoryText轨迹视图')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('没有可显示的轨迹')),
                              );
                            }
                          },
                          tooltip: '查看当前轨迹',
                          child: const Icon(Icons.fit_screen),
                        ),
                      ],
                    ),
                  ),
                  // 方向控制按钮
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          onPressed: () {
                            try {
                              final currentCenter = _mapController.camera.center;
                              _mapController.move(
                                LatLng(currentCenter.latitude + 0.01, currentCenter.longitude),
                                _mapController.camera.zoom,
                              );
                            } catch (e) {
                              debugPrint('移动操作失败: $e');
                            }
                          },
                          child: const Icon(Icons.keyboard_arrow_up),
                        ),
                        Row(
                          children: [
                            FloatingActionButton.small(
                              onPressed: () {
                                try {
                                  final currentCenter = _mapController.camera.center;
                                  _mapController.move(
                                    LatLng(currentCenter.latitude, currentCenter.longitude - 0.01),
                                    _mapController.camera.zoom,
                                  );
                                } catch (e) {
                                  debugPrint('移动操作失败: $e');
                                }
                              },
                              child: const Icon(Icons.keyboard_arrow_left),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              onPressed: () {
                                try {
                                  final currentCenter = _mapController.camera.center;
                                  _mapController.move(
                                    LatLng(currentCenter.latitude, currentCenter.longitude + 0.01),
                                    _mapController.camera.zoom,
                                  );
                                } catch (e) {
                                  debugPrint('移动操作失败: $e');
                                }
                              },
                              child: const Icon(Icons.keyboard_arrow_right),
                            ),
                          ],
                        ),
                        FloatingActionButton.small(
                          onPressed: () {
                            try {
                              final currentCenter = _mapController.camera.center;
                              _mapController.move(
                                LatLng(currentCenter.latitude - 0.01, currentCenter.longitude),
                                _mapController.camera.zoom,
                              );
                            } catch (e) {
                              debugPrint('移动操作失败: $e');
                            }
                          },
                          child: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ],
                    ),
                  ),
                  // 位置按钮
                  if (_currentLocation != null)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        onPressed: () {
                          _mapController.move(_currentLocation!, 15.0);
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                ],
                // 加载指示器
                if (_isLoading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
                // 位置加载指示器
                if (_isLocationLoading)
                  const Positioned(
                    top: 50,
                    left: 16,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('获取位置中...'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

