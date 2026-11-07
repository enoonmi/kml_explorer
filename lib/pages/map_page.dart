import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/location_controller.dart';
import '../models/kml_file.dart';
import '../models/kml_marker.dart';
import '../models/map_config.dart';
import '../models/tile_server.dart';
import '../services/settings_service.dart';
import '../services/tile_probe.dart';
import '../services/track_renderer.dart';
import '../services/webdav_service.dart';
import 'file_manager_page.dart';
import 'marker_info_dialog.dart';
import 'tile_server_dialogs.dart';
import 'webdav_settings_page.dart';

/// 地图主页。
///
/// 相比重构前从 2102 行降到约 600 行：底图探测交给 [TileServerProbe]，
/// 定位交给 [LocationController]，图层构建交给 [TrackRenderer]，
/// 设置读写交给 [SettingsService]。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final LocationController _location = LocationController();
  final TileServerProbe _probe = TileServerProbe();

  List<TileServer> _servers = List<TileServer>.from(kDefaultTileServers);
  int _currentIndex = 0;

  List<KmlFile> _kmlFiles = [];
  List<KmlFile> _filteredFiles = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _highlightPending = false;

  bool _mapReady = false;
  bool _loadingFiles = false;
  bool _showFileManager = true;
  String _networkStatus = '正在检查网络…';

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  TileServer get _current => _servers[_currentIndex];
  bool get _isChineseMap => _current.isChineseMap;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocationChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    _probe.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await WebDavService.instance.initialize();
    await SettingsService.loadMapConfig();

    final settings = await SettingsService.loadAll(_servers.length);
    if (!mounted) return;

    // 应用已保存的可见性与选中的供应商
    setState(() {
      _servers = [
        for (var i = 0; i < _servers.length; i++)
          _servers[i].copyWith(visible: settings.tileVisibility[i]),
      ];
      _showFileManager = settings.showFileManager;
      _currentIndex =
          settings.tileServerIndex.clamp(0, _servers.length - 1);
      _location.intervalSeconds = settings.locationInterval;
    });

    if (settings.isFirstRun) {
      await SettingsService.persistFirstRunDefaults(_servers);
    }

    await _loadKmlFiles();
    _mapReady = true;
    if (mounted) setState(() {});

    await _location.fetchCurrentPosition();
    if (_location.position != null && _mapReady) {
      _mapController.move(_location.position!, 15);
    }

    // 后台探测，不阻塞首屏
    unawaited(_refreshAllStatuses());
    unawaited(_checkNetwork());
  }

  Future<void> _checkNetwork() async {
    final ok = await _probe.hasNetwork();
    if (!mounted) return;
    setState(() {
      _networkStatus = ok ? '网络连接正常' : '网络连接异常（底图可能无法加载）';
    });
  }

  // ---------------------------------------------------------------- 底图

  Future<void> _refreshAllStatuses() async {
    for (var i = 0; i < _servers.length; i++) {
      if (!mounted) return;
      setState(() {
        _servers[i] = _servers[i].copyWith(status: TileServerStatus.testing);
      });

      final result = await _probe.probe(_servers[i]);
      if (!mounted) return;
      setState(() {
        _servers[i] = _servers[i].copyWith(
          status: result.available
              ? TileServerStatus.available
              : TileServerStatus.unavailable,
          errorMessage: result.errorMessage,
        );
      });
    }
    if (!mounted) return;

    // 只有当前选中的不可用才自动切换，绝不覆盖用户的选择
    final current = _servers[_currentIndex];
    if (current.status == TileServerStatus.unavailable) {
      final fallback = _servers.indexWhere(
        (s) => s.visible && s.status == TileServerStatus.available,
      );
      if (fallback != -1) {
        setState(() => _currentIndex = fallback);
        await SettingsService.saveTileServerIndex(fallback);
        _rebuildLayers();
        _toast('当前底图不可用，已自动切换到 ${_servers[fallback].name}');
      }
    }
  }

  Future<void> _testOne(int index) async {
    final result = await _probe.probe(_servers[index]);
    if (!mounted) return;
    setState(() {
      _servers[index] = _servers[index].copyWith(
        status: result.available
            ? TileServerStatus.available
            : TileServerStatus.unavailable,
        errorMessage: result.errorMessage,
      );
    });
  }

  Future<void> _selectTileServer(int index) async {
    if (index == _currentIndex) return;
    final previous = _currentIndex;
    setState(() => _currentIndex = index);
    await SettingsService.saveTileServerIndex(index);
    _rebuildLayers(); // 坐标系可能变化，必须重建

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已切换到 ${_servers[index].name}'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              setState(() => _currentIndex = previous);
              await SettingsService.saveTileServerIndex(previous);
              _rebuildLayers();
            },
          ),
        ),
      );
  }

  Future<void> _openTileSelector() async {
    final picked = await showTileServerSelector(
      context,
      servers: _servers,
      currentIndex: _currentIndex,
      onRetest: () async {
        Navigator.of(context).pop();
        await _refreshAllStatuses();
      },
    );
    if (picked != null) await _selectTileServer(picked);
  }

  Future<void> _openTileSettings() async {
    await showTileServerSettings(
      context,
      servers: _servers,
      onApply: (visibility) async {
        setState(() {
          for (var i = 0; i < _servers.length; i++) {
            _servers[i] = _servers[i].copyWith(visible: visibility[i]);
          }
        });
        await SettingsService.saveTileVisibility(_servers);
        // 若当前选中的被隐藏了，退到第一个可见项
        if (!_servers[_currentIndex].visible) {
          final first = _servers.indexWhere((s) => s.visible);
          if (first != -1) await _selectTileServer(first);
        }
      },
      onTestOne: _testOne,
      onTestAll: _refreshAllStatuses,
    );
  }

  Widget _buildTileLayer() {
    final server = _current;
    final url = server.requiresTiandituKey
        ? MapConfig.getTiandituUrl(server.url)
        : server.url;

    return TileLayer(
      urlTemplate: url,
      userAgentPackageName: 'com.example.kml_explorer',
      subdomains: server.subdomains ?? const [],
      minZoom: 3,
      maxZoom: 18,
      keepBuffer: 2,
      // 不挂 1x1 透明兜底图，让加载失败可见（原先失败是静默的）
      errorImage: null,
    );
  }

  // ---------------------------------------------------------------- 轨迹

  Future<void> _loadKmlFiles() async {
    if (!mounted) return;
    setState(() => _loadingFiles = true);
    try {
      final files = await KmlFileManager.loadKmlFiles();
      if (!mounted) return;
      setState(() {
        _kmlFiles = files;
        _loadingFiles = false;
      });
      _rebuildLayers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFiles = false);
      _toast('加载轨迹列表失败: $e');
    }
  }

  void _rebuildLayers() {
    setState(() {
      _polylines = TrackRenderer.buildPolylines(
        _kmlFiles,
        isChineseMap: _isChineseMap,
      );
      _markers = TrackRenderer.buildMarkers(
        _kmlFiles,
        isChineseMap: _isChineseMap,
        onTap: _showMarkerInfo,
      );
    });
  }

  void _showMarkerInfo(KmlMarker marker) {
    showDialog<String>(
      context: context,
      builder: (_) => MarkerInfoDialog(marker: marker),
    ).then((result) {
      if (result == 'navigate' && mounted) {
        _mapController.move(marker.position, 15);
      }
    });
  }

  void _jumpToTrack(KmlFile file) {
    if (file.visiblePoints.isEmpty) {
      _toast('该轨迹没有可显示的点');
      return;
    }
    final bounds = TrackRenderer.boundsOf([file], isChineseMap: _isChineseMap);
    if (bounds == null) {
      _toast('无法计算轨迹范围');
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );

    // 高亮 5 秒：用加粗参数重建一次，再复原
    if (_highlightPending) return;
    _highlightPending = true;
    final index = _polylines.indexWhere(
      (p) => p.points.length == file.visiblePoints.length,
    );
    if (index != -1) {
      final target = _polylines[index];
      setState(() {
        _polylines[index] = Polyline(
          points: target.points,
          color: target.color,
          strokeWidth: target.strokeWidth + 2,
        );
      });
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        _highlightPending = false;
        _rebuildLayers();
      });
    } else {
      _highlightPending = false;
    }
    _toast('已定位到 ${file.displayName}');
  }

  void _fitToVisible() {
    final source = _filteredFiles.isNotEmpty ? _filteredFiles : _kmlFiles;
    final bounds = TrackRenderer.boundsOf(source, isChineseMap: _isChineseMap);
    if (bounds == null) {
      _toast('没有可显示的轨迹');
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  void _onFilesChanged(List<KmlFile> files) {
    setState(() => _kmlFiles = files);
    _rebuildLayers();
  }

  void _onFilteredFilesChanged(List<KmlFile> filtered) {
    setState(() => _filteredFiles = filtered);
  }

  // ---------------------------------------------------------------- 定位

  Future<void> _toggleLocation() async {
    await _location.toggle();
    if (!mounted) return;
    if (_location.isTracking) {
      if (_location.position != null) {
        _mapController.move(_location.position!, 15);
      }
      _toast('已开始实时定位，间隔 ${_location.intervalSeconds} 秒');
    } else {
      _toast('已停止实时定位');
    }
  }

  Future<void> _openLocationSettings() async {
    const options = [1, 3, 5, 10, 30];
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('位置设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('位置更新间隔'),
            const SizedBox(height: 8),
            DropdownButton<int>(
              isExpanded: true,
              value: options.contains(_location.intervalSeconds)
                  ? _location.intervalSeconds
                  : 5,
              items: [
                for (final s in options)
                  DropdownMenuItem(value: s, child: Text('$s 秒')),
              ],
              onChanged: (v) => Navigator.of(dialogContext).pop(v),
            ),
            const SizedBox(height: 16),
            if (_location.lastUpdated != null) ...[
              Text('最后更新：${_fmtTime(_location.lastUpdated!)}'),
              Text('精度：${_location.accuracy.toStringAsFixed(1)} m'),
              if (_location.speed > 0)
                Text(
                  '速度：${(_location.speed * 3.6).toStringAsFixed(1)} km/h',
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (picked != null) {
      await _location.setInterval(picked);
      await SettingsService.saveLocationInterval(picked);
      _toast('位置更新间隔已设为 $picked 秒');
    }
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- 杂项

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleFileManager() async {
    setState(() => _showFileManager = !_showFileManager);
    await SettingsService.saveShowFileManager(_showFileManager);
  }

  void _showAppInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关于 KML Explorer'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KML Explorer 1.0.0'),
            SizedBox(height: 8),
            Text('KML 轨迹文件管理与查看器'),
            Text('支持 10+ 地图供应商、轨迹样式编辑与 WebDAV 同步'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  void _showDiagnostics() {
    final available = _servers
        .where((s) => s.status == TileServerStatus.available)
        .length;
    final visible = _servers.where((s) => s.visible).length;

    String zoom = '未就绪';
    String center = '未就绪';
    try {
      zoom = _mapController.camera.zoom.toStringAsFixed(2);
      final c = _mapController.camera.center;
      center = '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}';
    } catch (_) {}

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('网络', _networkStatus),
              _kv('当前底图', _current.name),
              _kv('坐标系', _isChineseMap ? 'GCJ-02' : 'WGS-84'),
              _kv('底图状态', _servers[_currentIndex].status.name),
              _kv('可用/可见', '$available / $visible（共 ${_servers.length}）'),
              if (_current.errorMessage != null)
                _kv('错误', _current.errorMessage!),
              _kv('缩放', zoom),
              _kv('中心', center),
              _kv('定位', _location.isTracking ? '进行中' : '已停止'),
              _kv('更新间隔', '${_location.intervalSeconds} 秒'),
              _kv('已加载文件', '${_kmlFiles.length}'),
              _kv('可见轨迹', '${_polylines.length}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _refreshAllStatuses();
            },
            child: const Text('重新测试'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(k, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  void _openSettingsMenu() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('设置'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showAppInfo();
            },
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('关于'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WebDavSettingsPage(),
                ),
              );
            },
            child: const ListTile(
              leading: Icon(Icons.cloud_outlined),
              title: Text('WebDAV 同步'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openTileSettings();
            },
            child: const ListTile(
              leading: Icon(Icons.layers_outlined),
              title: Text('地图供应商'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showTiandituSettings(context);
            },
            child: const ListTile(
              leading: Icon(Icons.key_outlined),
              title: Text('天地图密钥'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openLocationSettings();
            },
            child: const ListTile(
              leading: Icon(Icons.my_location_outlined),
              title: Text('位置'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KML Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettingsMenu,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '诊断',
            onPressed: _showDiagnostics,
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: '底图：${_current.name}',
            onPressed: _openTileSelector,
          ),
          if (_isDesktop)
            IconButton(
              icon: Icon(_showFileManager ? Icons.chevron_left : Icons.menu),
              tooltip: _showFileManager ? '隐藏列表' : '显示列表',
              onPressed: _toggleFileManager,
            ),
        ],
      ),
      body: Row(
        children: [
          if (_isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _showFileManager ? 320 : 0,
              child: _showFileManager
                  ? FileManagerPage(
                      onFilesChanged: _onFilesChanged,
                      onTrackSelected: _jumpToTrack,
                      onFilteredFilesChanged: _onFilteredFilesChanged,
                    )
                  : const SizedBox.shrink(),
            ),
          Expanded(child: _buildMapArea()),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    return Stack(
      children: [
        if (_mapReady)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _location.position ?? const LatLng(39.9042, 116.4074),
              initialZoom: _location.position != null ? 15 : 10,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              _buildTileLayer(),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(markers: _markers),
              if (_location.position != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _location.position!,
                      width: 24,
                      height: 24,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(_current.attribution),
                ],
              ),
            ],
          )
        else
          const Center(child: CircularProgressIndicator()),

        if (_loadingFiles)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),

        // 右侧缩放 / 适配
        if (_mapReady)
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                _fab(Icons.add, '放大', () {
                  final c = _mapController.camera;
                  _mapController.move(c.center, (c.zoom + 1).clamp(3, 18));
                }),
                const SizedBox(height: 8),
                _fab(Icons.remove, '缩小', () {
                  final c = _mapController.camera;
                  _mapController.move(c.center, (c.zoom - 1).clamp(3, 18));
                }),
                const SizedBox(height: 8),
                _fab(Icons.fit_screen, '适配轨迹', _fitToVisible),
              ],
            ),
          ),

        // 左下定位
        if (_mapReady)
          Positioned(
            left: 12,
            bottom: 12,
            child: Column(
              children: [
                _fab(
                  _location.isTracking
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  _location.isTracking ? '停止定位' : '开始定位',
                  _toggleLocation,
                  background:
                      _location.isTracking ? Colors.green : Colors.grey,
                ),
                const SizedBox(height: 8),
                _fab(Icons.tune, '位置设置', _openLocationSettings),
                const SizedBox(height: 8),
                _fab(Icons.my_location, '回到当前位置', () {
                  if (_location.position != null) {
                    _mapController.move(_location.position!, 15);
                  } else {
                    _toast('尚未获取到当前位置');
                  }
                }),
              ],
            ),
          ),

        // 实时定位信息卡
        if (_location.isTracking && _location.position != null)
          Positioned(
            top: 12,
            left: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 8),
                        SizedBox(width: 6),
                        Text(
                          '实时定位中',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_location.lastUpdated != null)
                      Text(
                        '更新 ${_fmtTime(_location.lastUpdated!)}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    Text(
                      '精度 ${_location.accuracy.toStringAsFixed(1)} m',
                      style: const TextStyle(fontSize: 10),
                    ),
                    if (_location.speed > 0)
                      Text(
                        '速度 ${(_location.speed * 3.6).toStringAsFixed(1)} km/h',
                        style: const TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fab(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    Color? background,
  }) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      tooltip: tooltip,
      backgroundColor: background,
      foregroundColor: background != null ? Colors.white : null,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
