import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' show min, max;
import 'dart:ui' as ui;
import 'dart:async';
import '../models/kml_file.dart';

class TrackEditPage extends StatefulWidget {
  final KmlFile kmlFile;
  final Function(KmlFile) onTrackUpdated;

  const TrackEditPage({
    super.key,
    required this.kmlFile,
    required this.onTrackUpdated,
  });

  @override
  State<TrackEditPage> createState() => _TrackEditPageState();
}

class _TrackEditPageState extends State<TrackEditPage> {
  late TextEditingController _nameController;
  late Color _selectedColor;
  late double _trackWidth;
  late RangeValues _pointRange;
  late int _maxPoints;
  
  // 防抖定时器
  Timer? _debounceTimer;
  
  // 延迟加载标志
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.kmlFile.displayName);
    _selectedColor = widget.kmlFile.trackColor;
    _trackWidth = widget.kmlFile.trackWidth;
    _maxPoints = widget.kmlFile.points.length - 1;
    _pointRange = RangeValues(
      widget.kmlFile.startPointIndex.toDouble(),
      widget.kmlFile.endPointIndex.toDouble(),
    );
    
    // 延迟加载复杂组件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _saveChanges() {
    final updatedFile = widget.kmlFile.copyWith(
      displayName: _nameController.text.trim(),
      trackColor: _selectedColor,
      trackWidth: _trackWidth,
      startPointIndex: _pointRange.start.round(),
      endPointIndex: _pointRange.end.round(),
    );
    
    widget.onTrackUpdated(updatedFile);
    Navigator.of(context).pop();
  }

  // 计算合适的divisions数量，避免性能问题
  int _getDivisions() {
    if (_maxPoints <= 100) return _maxPoints;
    if (_maxPoints <= 1000) return 100;
    if (_maxPoints <= 10000) return 50;
    return 20; // 对于非常大的轨迹，使用较少的divisions
  }

  // 防抖更新状态
  void _debouncedSetState(VoidCallback fn) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(fn);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑轨迹'),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoaded ? _buildContent() : _buildLoadingContent(),
    );
  }

  Widget _buildLoadingContent() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载轨迹编辑界面...'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final divisions = _getDivisions();
    final isLargeTrack = widget.kmlFile.points.length > 10000;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 轨迹名称
          const Text(
            '轨迹名称',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入轨迹名称',
            ),
          ),
          const SizedBox(height: 24),

          // 轨迹颜色
          const Text(
            '轨迹颜色',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('选择颜色'),
                  content: SingleChildScrollView(
                    child: ColorPicker(
                      pickerColor: _selectedColor,
                      onColorChanged: (color) {
                        setState(() {
                          _selectedColor = color;
                        });
                      },
                      pickerAreaHeightPercent: 0.8,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _selectedColor,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '点击选择颜色',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 轨迹粗细
          const Text(
            '轨迹粗细',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _trackWidth,
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  label: _trackWidth.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _trackWidth = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _trackWidth.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 轨迹范围
          const Text(
            '轨迹范围',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '总轨迹点数: ${widget.kmlFile.points.length}',
            style: const TextStyle(color: Colors.grey),
          ),
          if (isLargeTrack) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '轨迹点数较多，建议使用简化的范围设置',
                      style: TextStyle(color: Colors.orange[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // 简化版范围设置
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('起始点', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '起始点索引',
                        ),
                        controller: TextEditingController(
                          text: _pointRange.start.round().toString(),
                        ),
                        onChanged: (value) {
                          final start = int.tryParse(value) ?? 0;
                          if (start >= 0 && start <= _maxPoints) {
                            _debouncedSetState(() {
                              _pointRange = RangeValues(
                                start.toDouble(),
                                _pointRange.end,
                              );
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('结束点', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '结束点索引',
                        ),
                        controller: TextEditingController(
                          text: _pointRange.end.round().toString(),
                        ),
                        onChanged: (value) {
                          final end = int.tryParse(value) ?? _maxPoints;
                          if (end >= 0 && end <= _maxPoints) {
                            _debouncedSetState(() {
                              _pointRange = RangeValues(
                                _pointRange.start,
                                end.toDouble(),
                              );
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            RangeSlider(
              values: _pointRange,
              min: 0,
              max: _maxPoints.toDouble(),
              divisions: divisions,
              labels: RangeLabels(
                _pointRange.start.round().toString(),
                _pointRange.end.round().toString(),
              ),
              onChanged: (values) {
                _debouncedSetState(() {
                  _pointRange = values;
                });
              },
            ),
          ],
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('起始点: ${_pointRange.start.round()}'),
              Text('结束点: ${_pointRange.end.round()}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '显示点数: ${_pointRange.end.round() - _pointRange.start.round() + 1}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // 预览 - 只对小型轨迹显示
          if (!isLargeTrack) ...[
            const Text(
              '预览',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: TrackPreviewPainter(
                  points: widget.kmlFile.points.map((p) => p.toLatLng()).toList(),
                  startIndex: _pointRange.start.round(),
                  endIndex: _pointRange.end.round(),
                  color: _selectedColor,
                  strokeWidth: _trackWidth,
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 32),
                    SizedBox(height: 8),
                    Text(
                      '轨迹点数过多，预览已禁用',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TrackPreviewPainter extends CustomPainter {
  final List<LatLng> points;
  final int startIndex;
  final int endIndex;
  final Color color;
  final double strokeWidth;

  TrackPreviewPainter({
    required this.points,
    required this.startIndex,
    required this.endIndex,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final visiblePoints = points.sublist(
      startIndex.clamp(0, points.length - 1),
      (endIndex + 1).clamp(startIndex, points.length),
    );

    if (visiblePoints.length < 2) return;

    // 对于大量点，进行采样以提高性能
    final sampledPoints = _samplePoints(visiblePoints, size.width);
    if (sampledPoints.length < 2) return;

    // 计算边界
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var point in sampledPoints) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    // 避免除零错误
    if (maxLat == minLat || maxLng == minLng) return;

    // 转换坐标到画布
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = ui.Path();
    bool first = true;

    for (var point in sampledPoints) {
      final x = (point.longitude - minLng) / (maxLng - minLng) * size.width;
      final y = (1 - (point.latitude - minLat) / (maxLat - minLat)) * size.height;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  // 对轨迹点进行采样，减少绘制负担
  List<LatLng> _samplePoints(List<LatLng> points, double canvasWidth) {
    if (points.length <= 100) return points; // 点数较少时不需要采样
    
    final maxPoints = (canvasWidth / 2).round(); // 根据画布宽度决定最大点数
    if (points.length <= maxPoints) return points;
    
    final step = points.length / maxPoints;
    final sampled = <LatLng>[];
    
    for (int i = 0; i < maxPoints; i++) {
      final index = (i * step).round();
      if (index < points.length) {
        sampled.add(points[index]);
      }
    }
    
    // 确保包含最后一个点
    if (sampled.last != points.last) {
      sampled.add(points.last);
    }
    
    return sampled;
  }

  @override
  bool shouldRepaint(covariant TrackPreviewPainter oldDelegate) {
    return oldDelegate.startIndex != startIndex ||
           oldDelegate.endIndex != endIndex ||
           oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.points != points;
  }
} 