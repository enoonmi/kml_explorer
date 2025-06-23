import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/kml_file.dart';
import 'track_edit_dialog.dart';
import '../services/webdav_service.dart';
import 'webdav_file_picker_page.dart';

class FileManagerPage extends StatefulWidget {
  final Function(List<KmlFile>) onFilesChanged;
  final Function(KmlFile) onTrackSelected;
  final Function(List<KmlFile>) onFilteredFilesChanged;

  const FileManagerPage({
    super.key, 
    required this.onFilesChanged,
    required this.onTrackSelected,
    required this.onFilteredFilesChanged,
  });

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  List<KmlFile> _kmlFiles = [];
  bool _isLoading = true;
  // 选中的标签集合 - 不能是final，因为需要在用户交互时动态修改
  // ignore: prefer_final_fields
  Set<String> _selectedCategories = {};
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadKmlFiles();
  }

  Future<void> _loadKmlFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await KmlFileManager.loadKmlFiles();
      if (mounted) {
        setState(() {
          _kmlFiles = files;
          _isLoading = false;
          _updateCategories();
          // 通知主界面当前筛选的文件列表
          _notifyFilteredFilesChanged();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载文件列表失败: $e')),
        );
      }
    }
  }

  void _updateCategories() {
    final categories = <String>{};
    for (final file in _kmlFiles) {
      categories.addAll(file.trackTags);
    }
    _categories = categories.toList()..sort();
  }

  List<KmlFile> get _filteredFiles {
    if (_selectedCategories.isEmpty) {
      return _kmlFiles; // 没有选择标签时显示全部
    }
    return _kmlFiles.where((file) => 
      file.trackTags.any((tag) => _selectedCategories.contains(tag))
    ).toList();
  }

  // 通知主界面当前筛选的文件列表
  void _notifyFilteredFilesChanged() {
    widget.onFilteredFilesChanged(_filteredFiles);
  }

  // 更新文件可见性以匹配标签筛选
  Future<void> _updateFileVisibilityForTags() async {
    try {
      // 如果当前没有文件，可能是元数据损坏，不执行更新
      if (_kmlFiles.isEmpty) {
        return;
      }
      
      bool hasChanges = false;
      
      if (_selectedCategories.isEmpty) {
        // 没有选择标签时，显示所有文件
        for (final file in _kmlFiles) {
          if (!file.isVisible) {
            await KmlFileManager.updateFileVisibility(file.name, true);
            hasChanges = true;
          }
        }
      } else {
        // 选择标签时，只显示匹配的文件
        for (final file in _kmlFiles) {
          final shouldBeVisible = file.trackTags.any((tag) => _selectedCategories.contains(tag));
          if (file.isVisible != shouldBeVisible) {
            await KmlFileManager.updateFileVisibility(file.name, shouldBeVisible);
            hasChanges = true;
          }
        }
      }
      
      // 只有在有变化时才重新加载文件列表
      if (hasChanges) {
        await _loadKmlFiles();
        widget.onFilesChanged(_kmlFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新轨迹显示失败: $e')),
        );
      }
    }
  }

  Future<void> _importKmlFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kml'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final fileName = file.path.split(Platform.pathSeparator).last;
        
        // 检查文件是否已存在
        final existingFiles = await KmlFileManager.loadKmlFiles();
        final existingFileNames = existingFiles.map((f) => f.name).toSet();
        
        if (existingFileNames.contains(fileName)) {
          if (mounted) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('文件已存在'),
                content: Text('文件 "$fileName" 已经存在，是否要覆盖？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('覆盖'),
                  ),
                ],
              ),
            );
            
            if (proceed != true) return;
          }
        }
        
        await KmlFileManager.saveKmlFile(file);
        await _loadKmlFiles();
        
        widget.onFilesChanged(_kmlFiles);
        
        if (mounted) {
          final message = existingFileNames.contains(fileName) 
              ? '文件覆盖成功' 
              : '文件导入成功';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
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

  Future<void> _editTrack(KmlFile file) async {
    try {
      debugPrint('开始编辑轨迹: ${file.displayName}, 轨迹点数: ${file.points.length}');
      
      // 检查轨迹点数，如果太多则显示警告
      if (file.points.length > 50000) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('轨迹点数过多'),
            content: Text(
              '该轨迹包含 ${file.points.length} 个点，编辑可能会比较慢。是否继续？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        );
        
        if (proceed != true) return;
      }
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (dialogContext) => TrackEditDialog(
          kmlFile: file,
          onTrackUpdated: (updatedFile) async {
            try {
              debugPrint('保存轨迹设置: ${updatedFile.displayName}');
              await KmlFileManager.updateFileStyle(
                updatedFile.name,
                displayName: updatedFile.displayName,
                trackColor: updatedFile.trackColor,
                trackWidth: updatedFile.trackWidth,
                startPointIndex: updatedFile.startPointIndex,
                endPointIndex: updatedFile.endPointIndex,
              );
              await _loadKmlFiles();
              widget.onFilesChanged(_kmlFiles);
              
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('轨迹设置已保存')),
                    );
                  }
                });
              }
            } catch (e) {
              debugPrint('保存轨迹设置失败: $e');
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('保存轨迹设置失败: $e')),
                    );
                  }
                });
              }
            }
          },
        ),
      );
      
      debugPrint('轨迹编辑完成');
    } catch (e) {
      debugPrint('打开轨迹编辑页面失败: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('打开轨迹编辑页面失败: $e')),
            );
          }
        });
      }
    }
  }

  Future<void> _deleteFile(KmlFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件 "${file.displayName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await KmlFileManager.deleteKmlFile(file.name);
        await _loadKmlFiles();
        widget.onFilesChanged(_kmlFiles);
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('文件删除成功')),
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('删除文件失败: $e')),
              );
            }
          });
        }
      }
    }
  }

  Future<void> _toggleFileVisibility(KmlFile file) async {
    try {
      await KmlFileManager.updateFileVisibility(file.name, !file.isVisible);
      await _loadKmlFiles();
      widget.onFilesChanged(_kmlFiles);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新文件状态失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KML 文件管理'),
        automaticallyImplyLeading: false,
        actions: [
          // 恢复损坏文件按钮
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _restoreCorruptedFiles,
            tooltip: '恢复损坏文件',
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: _removeDuplicates,
            tooltip: '去重',
          ),
          if (WebDavService.instance.isEnabled)
            IconButton(
              icon: const Icon(Icons.cloud_download),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => WebDavFilePickerPage(
                      onFilesSelected: (files) {
                        _loadKmlFiles();
                        widget.onFilesChanged(_kmlFiles);
                      },
                    ),
                  ),
                );
              },
              tooltip: '从WebDAV导入',
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _importKmlFile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _kmlFiles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('暂无 KML 文件', style: TextStyle(fontSize: 18)),
                      SizedBox(height: 8),
                      Text('点击右上角按钮导入文件', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 分类选择器
                    if (_categories.length > 1)
                      Container(
                        padding: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _categories.map((category) {
                              final isSelected = _selectedCategories.contains(category);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedCategories.add(category);
                                      } else {
                                        _selectedCategories.remove(category);
                                      }
                                    });
                                    // 通知主界面当前筛选的文件列表
                                    _notifyFilteredFilesChanged();
                                    // 更新地图上的轨迹显示
                                    _updateFileVisibilityForTags();
                                  },
                                  selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                  checkmarkColor: Theme.of(context).primaryColor,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    // 文件列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredFiles.length,
                        itemBuilder: (context, index) {
                          final file = _filteredFiles[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: InkWell(
                              onTap: () {
                                widget.onTrackSelected(file);
                              },
                              child: Container(
                                height: 90, // 增加高度避免溢出
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    // 颜色指示器
                                    Container(
                                      width: 8,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        color: file.trackColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 文件信息
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // 文件名和起点终点信息
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _getCleanFileName(file.displayName),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: file.isVisible ? Colors.black : Colors.grey,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (_getStartEndInfo(file).isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    _getStartEndInfo(file),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          // 轨迹时间
                                          Text(
                                            _getTrackTimeDisplay(file),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[500],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          // 标签（如果有）
                                          if (file.trackTags.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Wrap(
                                                spacing: 4,
                                                runSpacing: 1,
                                                children: file.trackTags.take(3).map((tag) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      tag,
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.blue,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // 状态指示器和操作按钮
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // 云端保存状态指示灯
                                        if (WebDavService.instance.isEnabled)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: file.isCloudSaved ? Colors.green : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                            margin: const EdgeInsets.only(bottom: 4),
                                          ),
                                        // 可见性图标
                                        Icon(
                                          file.isVisible ? Icons.visibility : Icons.visibility_off,
                                          size: 16,
                                          color: file.isVisible ? Colors.green : Colors.grey,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    // 操作按钮
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // 手动上传到WebDAV按钮
                                        if (WebDavService.instance.isEnabled && !file.isCloudSaved)
                                          IconButton(
                                            icon: const Icon(Icons.cloud_upload, size: 16),
                                            onPressed: () => _uploadToWebDav(file),
                                            tooltip: '上传到WebDAV',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 16),
                                          onPressed: () => _editTrack(file),
                                          tooltip: '编辑轨迹',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            file.isVisible ? Icons.visibility_off : Icons.visibility,
                                            size: 16,
                                          ),
                                          onPressed: () => _toggleFileVisibility(file),
                                          tooltip: file.isVisible ? '隐藏轨迹' : '显示轨迹',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 16),
                                          onPressed: () => _deleteFile(file),
                                          tooltip: '删除文件',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  // 新增：手动上传到WebDAV
  Future<void> _uploadToWebDav(KmlFile file) async {
    try {
      final webDavService = WebDavService.instance;
      if (webDavService.isEnabled) {
        final fileObj = File(file.filePath);
        final success = await webDavService.uploadFile(fileObj, file.name);
        
        if (success) {
          // 更新云端状态
          await KmlFileManager.updateCloudStatus(file.name, true);
          // 重新加载文件列表
          await _loadKmlFiles();
          widget.onFilesChanged(_kmlFiles);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件上传到WebDAV成功')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件上传到WebDAV失败')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传到WebDAV时出错: $e')),
        );
      }
    }
  }

  // 恢复损坏的文件
  Future<void> _restoreCorruptedFiles() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复损坏文件'),
          content: const Text('检测到元数据文件可能已损坏。是否尝试从备份恢复？\n\n如果恢复失败，将清理损坏的文件并重新开始。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      
      // 尝试从备份恢复
      final restored = await KmlFileManager.restoreFromBackup();
      
      if (restored) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件恢复成功')),
          );
        }
        await _loadKmlFiles();
        widget.onFilesChanged(_kmlFiles);
      } else {
        // 恢复失败，清理损坏文件
        await KmlFileManager.clearCorruptedMetadata();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('恢复失败，已清理损坏文件')),
          );
        }
        await _loadKmlFiles();
        widget.onFilesChanged(_kmlFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复文件时出错: $e')),
        );
      }
    }
  }

  // 获取清理后的文件名（去除日期时间前缀）
  String _getCleanFileName(String fileName) {
    // 匹配常见的日期时间前缀格式
    // 支持格式：2025-06-0210_28、2025-06-02 10:28、2025-06-02_10:28等
    final dateTimePattern = RegExp(r'^\d{4}-\d{2}-\d{2}\s*_?\d{2}:\d{2}(?:_\d{2})?_?');
    final cleanName = fileName.replaceAll(dateTimePattern, '');
    
    // 如果清理后为空，返回原文件名
    if (cleanName.trim().isEmpty) {
      return fileName;
    }
    
    return cleanName.trim();
  }

  // 获取起点终点信息
  String _getStartEndInfo(KmlFile file) {
    String? startName;
    String? endName;
    
    // 从所有标记点中查找起点和终点信息
    for (final marker in file.markers) {
      if (marker.extendedData.containsKey('PosStartName')) {
        startName = marker.extendedData['PosStartName'];
      }
      if (marker.extendedData.containsKey('PosEndName')) {
        endName = marker.extendedData['PosEndName'];
      }
    }
    
    if (startName != null && endName != null) {
      // 简化显示格式，去除重复的"公园"等词汇
      final cleanStart = _simplifyLocationName(startName);
      final cleanEnd = _simplifyLocationName(endName);
      return '$cleanStart-$cleanEnd';
    } else if (startName != null) {
      return '起点:${_simplifyLocationName(startName)}';
    } else if (endName != null) {
      return '终点:${_simplifyLocationName(endName)}';
    } else {
      return ''; // 如果没有起点终点信息，返回空字符串
    }
  }

  // 简化地点名称
  String _simplifyLocationName(String name) {
    // 去除常见的重复词汇
    return name
        .replaceAll('公园', '')
        .replaceAll('停车场', '')
        .replaceAll('入口', '')
        .replaceAll('(南入口)', '')
        .replaceAll('(北入口)', '')
        .replaceAll('(东入口)', '')
        .replaceAll('(西入口)', '')
        .trim();
  }

  // 获取轨迹记录时间显示
  String _getTrackTimeDisplay(KmlFile file) {
    if (file.points.isEmpty) {
      return '无时间信息';
    }
    
    // 获取轨迹的第一个和最后一个时间点
    final firstTime = file.points.first.timestamp;
    final lastTime = file.points.last.timestamp;
    
    // 如果只有一个时间点，或者时间相同，只显示一个时间
    if (firstTime == lastTime) {
      return _formatDateTime(firstTime);
    }
    
    // 如果时间跨度不大（同一天），只显示日期
    if (firstTime.year == lastTime.year && 
        firstTime.month == lastTime.month && 
        firstTime.day == lastTime.day) {
      return _formatDate(firstTime);
    }
    
    // 时间跨度大，显示日期范围
    return '${_formatDate(firstTime)} - ${_formatDate(lastTime)}';
  }

  // 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // 格式化日期
  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  // 新增：去重功能
  Future<void> _removeDuplicates() async {
    try {
      // 按文件名分组，找出重复的文件
      final Map<String, List<KmlFile>> groupedFiles = {};
      for (final file in _kmlFiles) {
        final key = file.name.toLowerCase(); // 不区分大小写
        groupedFiles.putIfAbsent(key, () => []).add(file);
      }

      final duplicates = <KmlFile>[];
      for (final group in groupedFiles.values) {
        if (group.length > 1) {
          // 保留最新的文件（导入日期最新的），删除其他重复文件
          group.sort((a, b) => b.importDate.compareTo(a.importDate));
          duplicates.addAll(group.skip(1)); // 跳过第一个（最新的）
        }
      }

      // 如果没有通过文件名找到重复，尝试通过文件内容哈希检查
      if (duplicates.isEmpty) {
        final contentHashes = <String, List<KmlFile>>{};
        
        for (final file in _kmlFiles) {
          try {
            final fileObj = File(file.filePath);
            if (await fileObj.exists()) {
              final content = await fileObj.readAsString();
              // 简单的哈希：使用文件大小和内容长度
              final hash = '${content.length}_${file.points.length}';
              contentHashes.putIfAbsent(hash, () => []).add(file);
            }
          } catch (e) {
            debugPrint('读取文件内容失败: ${file.name}, $e');
          }
        }

        for (final group in contentHashes.values) {
          if (group.length > 1) {
            // 按导入日期排序，保留最新的
            group.sort((a, b) => b.importDate.compareTo(a.importDate));
            duplicates.addAll(group.skip(1));
          }
        }
      }

      if (duplicates.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有发现重复文件')),
          );
        }
        return;
      }

      // 显示确认对话框
      if (mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发现重复文件'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发现 ${duplicates.length} 个重复文件：'),
                const SizedBox(height: 8),
                ...duplicates.take(5).map((file) => Text('• ${file.name}')),
                if (duplicates.length > 5)
                  Text('... 还有 ${duplicates.length - 5} 个文件'),
                const SizedBox(height: 8),
                const Text('将保留最新的文件，删除其他重复文件。是否继续？'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除重复文件'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      // 删除重复文件
      for (final file in duplicates) {
        await KmlFileManager.deleteKmlFile(file.name);
      }

      // 重新加载文件列表
      await _loadKmlFiles();
      widget.onFilesChanged(_kmlFiles);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功删除 ${duplicates.length} 个重复文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('去重操作失败: $e')),
        );
      }
    }
  }
} 