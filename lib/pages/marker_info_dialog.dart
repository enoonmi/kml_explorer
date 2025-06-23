import 'package:flutter/material.dart';
import '../models/kml_marker.dart';

class MarkerInfoDialog extends StatelessWidget {
  final KmlMarker marker;

  const MarkerInfoDialog({
    super.key,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_camera, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      marker.name.isNotEmpty ? marker.name : '图片标记点',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 图片显示
                    if (marker.imageUrl != null) ...[
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            marker.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('图片加载失败', style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // 基本信息
                    _buildInfoSection('基本信息', [
                      _buildInfoRow('ID', marker.id),
                      _buildInfoRow('名称', marker.name.isNotEmpty ? marker.name : '未命名'),
                      _buildInfoRow('时间', _formatDateTime(marker.timestamp)),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // 位置信息
                    _buildInfoSection('位置信息', [
                      _buildInfoRow('纬度', '${marker.position.latitude.toStringAsFixed(6)}°'),
                      _buildInfoRow('经度', '${marker.position.longitude.toStringAsFixed(6)}°'),
                      _buildInfoRow('海拔', '${marker.altitude.toStringAsFixed(2)} 米'),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // 运动信息
                    _buildInfoSection('运动信息', [
                      _buildInfoRow('速度', '${marker.speed.toStringAsFixed(2)} m/s'),
                    ]),
                    
                    // 文件信息
                    if (marker.imageFileName != null || marker.imageFileId != null) ...[
                      const SizedBox(height: 16),
                      _buildInfoSection('文件信息', [
                        if (marker.imageFileName != null)
                          _buildInfoRow('文件名', marker.imageFileName!),
                        if (marker.imageFileId != null)
                          _buildInfoRow('文件ID', marker.imageFileId!),
                      ]),
                    ],
                    
                    // 扩展数据
                    if (marker.extendedData.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoSection('扩展数据', [
                        for (var entry in marker.extendedData.entries)
                          _buildInfoRow(entry.key, entry.value),
                      ]),
                    ],
                    
                    // 描述信息
                    if (marker.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoSection('描述', [
                        _buildInfoRow('内容', _cleanDescription(marker.description)),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            
            // 底部按钮
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('关闭'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop('navigate');
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('导航到此位置'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _cleanDescription(String description) {
    // 移除HTML标签，保留纯文本
    return description
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
} 