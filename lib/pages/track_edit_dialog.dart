import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' show min, max;
import '../models/kml_file.dart';
import '../models/kml_parser.dart';

enum YAxisType {
  altitude('海拔'),
  speed('速度'),
  distance('里程');

  const YAxisType(this.label);
  final String label;
}

class TrackEditDialog extends StatefulWidget {
  final KmlFile kmlFile;
  final Function(KmlFile) onTrackUpdated;

  const TrackEditDialog({
    super.key,
    required this.kmlFile,
    required this.onTrackUpdated,
  });

  @override
  State<TrackEditDialog> createState() => _TrackEditDialogState();
}

class _TrackEditDialogState extends State<TrackEditDialog> {
  late TextEditingController _nameController;
  late Color _selectedColor;
  late double _trackWidth;
  late RangeValues _pointRange;
  late YAxisType _selectedYAxis;
  
  // 图表数据
  final List<FlSpot> _chartData = [];
  double _minY = 0;
  double _maxY = 0;
  String _yAxisLabel = '';
  String _yAxisUnit = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.kmlFile.displayName);
    _selectedColor = widget.kmlFile.trackColor;
    _trackWidth = widget.kmlFile.trackWidth;
    _selectedYAxis = YAxisType.altitude;
    _pointRange = RangeValues(
      widget.kmlFile.startPointIndex.toDouble(),
      widget.kmlFile.endPointIndex.toDouble(),
    );
    
    _updateChartData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateChartData() {
    final points = widget.kmlFile.points;
    _chartData.clear();
    
    switch (_selectedYAxis) {
      case YAxisType.altitude:
        _yAxisLabel = '海拔';
        _yAxisUnit = 'm';
        for (int i = 0; i < points.length; i++) {
          _chartData.add(FlSpot(i.toDouble(), points[i].altitude));
        }
        break;
      case YAxisType.speed:
        _yAxisLabel = '速度';
        _yAxisUnit = 'km/h';
        for (int i = 0; i < points.length; i++) {
          double speed = 0;
          
          // 优先使用KML文件中的速度数据
          if (points[i].speed != null) {
            speed = points[i].speed!;
          } else {
            // 如果没有速度数据，则根据距离和时间计算
            if (i > 0 && i < points.length - 1) {
              // 计算速度（改进计算）
              final prev = points[i - 1];
              final curr = points[i];
              final next = points[i + 1];
              
              final distance1 = _calculateDistance(prev, curr);
              final distance2 = _calculateDistance(curr, next);
              final time1 = curr.timestamp.difference(prev.timestamp).inSeconds;
              final time2 = next.timestamp.difference(curr.timestamp).inSeconds;
              
              if (time1 > 0 && time2 > 0) {
                final speed1 = distance1 / time1 * 3.6; // 转换为 km/h
                final speed2 = distance2 / time2 * 3.6;
                speed = (speed1 + speed2) / 2;
              } else if (time1 > 0) {
                speed = distance1 / time1 * 3.6;
              } else if (time2 > 0) {
                speed = distance2 / time2 * 3.6;
              }
            } else if (i > 0) {
              // 第一个点或最后一个点
              final prev = points[i - 1];
              final curr = points[i];
              final distance = _calculateDistance(prev, curr);
              final time = curr.timestamp.difference(prev.timestamp).inSeconds;
              if (time > 0) {
                speed = distance / time * 3.6;
              }
            }
          }
          
          _chartData.add(FlSpot(i.toDouble(), speed));
        }
        break;
      case YAxisType.distance:
        _yAxisLabel = '里程';
        _yAxisUnit = 'km';
        double totalDistance = 0;
        for (int i = 0; i < points.length; i++) {
          if (i > 0) {
            totalDistance += _calculateDistance(points[i - 1], points[i]);
          }
          _chartData.add(FlSpot(i.toDouble(), totalDistance));
        }
        break;
    }
    
    if (_chartData.isNotEmpty) {
      _minY = _chartData.map((spot) => spot.y).reduce(min);
      _maxY = _chartData.map((spot) => spot.y).reduce(max);
      if (_minY == _maxY) {
        _maxY = _minY + 1;
      }
    }
  }

  double _calculateDistance(TrackPoint p1, TrackPoint p2) {
    return Distance().distance(LatLng(p1.latitude, p1.longitude), 
                              LatLng(p2.latitude, p2.longitude)) / 1000; // 转换为 km
  }

  // 获取时间轴标签
  String _getTimeLabel(double value) {
    final index = value.toInt();
    if (index >= 0 && index < widget.kmlFile.points.length) {
      final timestamp = widget.kmlFile.points[index].timestamp;
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return '';
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 标题栏
            Row(
              children: [
                const Text(
                  '编辑轨迹',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 轨迹名称
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '轨迹名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 样式设置行 - 更紧凑的布局
            Row(
              children: [
                // 颜色选择 - 更小
                Expanded(
                  flex: 2,
                  child: GestureDetector(
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
                      height: 40,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          '颜色',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                
                // 线宽选择 - 更紧凑
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('线宽: ${_trackWidth.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _trackWidth,
                        min: 1.0,
                        max: 10.0,
                        divisions: 18,
                        onChanged: (value) {
                          setState(() {
                            _trackWidth = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // 纵坐标选择
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('纵坐标:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      DropdownButton<YAxisType>(
                        value: _selectedYAxis,
                        isExpanded: true,
                        items: YAxisType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.label, style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedYAxis = value;
                              _updateChartData();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 图表区域
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // 图表标题
                      Text(
                        '$_yAxisLabel变化图 ($_yAxisUnit)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // 图表
                      Expanded(
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 60,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 10),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    // 显示时间轴标签
                                    final timeLabel = _getTimeLabel(value);
                                    if (timeLabel.isNotEmpty && value.toInt() % 50 == 0) {
                                      return Text(
                                        timeLabel,
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: true),
                            minX: 0,
                            maxX: (widget.kmlFile.points.length - 1).toDouble(),
                            minY: _minY,
                            maxY: _maxY,
                            lineBarsData: [
                              LineChartBarData(
                                spots: _chartData,
                                isCurved: false,
                                color: _selectedColor,
                                barWidth: _trackWidth,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: _selectedColor.withValues(alpha: 0.1),
                                ),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final pointIndex = spot.x.toInt();
                                    final point = widget.kmlFile.points[pointIndex];
                                    return LineTooltipItem(
                                      '点 ${pointIndex + 1}\n$_yAxisLabel: ${spot.y.toStringAsFixed(2)} $_yAxisUnit\n时间: ${point.timestamp.toString().substring(11, 19)}',
                                      const TextStyle(color: Colors.white),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 范围选择器
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '显示范围: ${_pointRange.start.round() + 1} - ${_pointRange.end.round() + 1} (共 ${widget.kmlFile.points.length} 个点)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                RangeSlider(
                  values: _pointRange,
                  min: 0,
                  max: (widget.kmlFile.points.length - 1).toDouble(),
                  divisions: widget.kmlFile.points.length > 1000 ? 100 : null,
                  labels: RangeLabels(
                    (_pointRange.start + 1).round().toString(),
                    (_pointRange.end + 1).round().toString(),
                  ),
                  onChanged: (values) {
                    setState(() {
                      _pointRange = values;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveChanges,
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 