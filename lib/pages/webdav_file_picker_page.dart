import 'package:flutter/material.dart';
import '../models/kml_file.dart';
import '../services/webdav_service.dart';
import 'dart:io';

class WebDavFilePickerPage extends StatefulWidget {
  final Function(List<String>)? onFilesSelected;
  
  const WebDavFilePickerPage({
    super.key,
    this.onFilesSelected,
  });

  @override
  State<WebDavFilePickerPage> createState() => _WebDavFilePickerPageState();
}

class _WebDavFilePickerPageState extends State<WebDavFilePickerPage> {
  final WebDavService _webDavService = WebDavService.instance;
  List<WebDavFile> _files = [];
  bool _isLoading = false;
  final Set<String> _selectedFiles = {};
  Set<String> _localKmlNames = {}; // 本地已加载的KML文件名

  double _downloadProgress = 0.0; // 下载进度
  String? _currentDownloading;    // 当前下载的文件名

  bool get _isDesktop => !Platform.isAndroid && !Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _loadLocalKmlNames();
    _loadFiles();
  }

  Future<void> _loadLocalKmlNames() async {
    final localFiles = await KmlFileManager.loadKmlFiles();
    setState(() {
      _localKmlNames = localFiles.map((e) => e.name).toSet();
    });
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (!_webDavService.isEnabled) {
        throw Exception('WebDAV服务未启用，请先在设置中配置WebDAV');
      }
      final isConnected = await _webDavService.ping();
      if (!isConnected) {
        throw Exception('无法连接到WebDAV服务器，请检查网络连接和服务器配置');
      }
      final files = await _webDavService.listFiles();
      await _loadLocalKmlNames(); // 刷新本地文件名
      setState(() {
        _files = files;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功加载 ${files.length} 个KML文件'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载文件失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _downloadAndLoadFiles() async {
    if (_selectedFiles.isEmpty) return;

    setState(() {
      _isLoading = true;
      _downloadProgress = 0.0;
      _currentDownloading = null;
    });

    try {
      // 过滤掉已存在的文件
      final filesToDownload = _selectedFiles.where((fileName) => !_localKmlNames.contains(fileName)).toList();
      final skippedCount = _selectedFiles.length - filesToDownload.length;
      
      if (filesToDownload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所有选中的文件都已存在，无需下载')),
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      final total = filesToDownload.length;
      int finished = 0;
      
      for (final fileName in filesToDownload) {
        setState(() {
          _currentDownloading = fileName;
          _downloadProgress = finished / total;
        });
        
        final file = await _webDavService.downloadFile(fileName);
        if (file != null) {
          await KmlFileManager.saveKmlFileFromWebDav(file, fileName);
        }
        finished++;
        setState(() {
          _downloadProgress = finished / total;
        });
      }

      if (mounted) {
        String message = '成功下载 ${filesToDownload.length} 个文件';
        if (skippedCount > 0) {
          message += '，跳过 $skippedCount 个重复文件';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        widget.onFilesSelected?.call(_selectedFiles.toList());
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载文件失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _downloadProgress = 0.0;
        _currentDownloading = null;
      });
    }
  }

  // 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  // 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedFiles.addAll(_files.map((f) => f.name));
      } else {
        _selectedFiles.clear();
      }
    });
  }

  bool get _isAllSelected => _files.isNotEmpty && _selectedFiles.length == _files.length;

  @override
  Widget build(BuildContext context) {
    final progressBar = (_isLoading && _selectedFiles.isNotEmpty)
        ? Column(
            children: [
              LinearProgressIndicator(value: _downloadProgress),
              if (_currentDownloading != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('正在下载: $_currentDownloading', style: const TextStyle(fontSize: 14)),
                ),
            ],
          )
        : const SizedBox.shrink();

    final content = _isLoading
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              progressBar,
              if (!_selectedFiles.isNotEmpty)
                const Center(child: CircularProgressIndicator()),
            ],
          )
        : RefreshIndicator(
            onRefresh: _loadFiles,
            child: _files.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('没有找到KML文件', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        SizedBox(height: 8),
                        Text('下拉刷新或点击刷新按钮', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _files.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // 顶部全选复选框
                        return CheckboxListTile(
                          title: const Text('全选'),
                          value: _isAllSelected,
                          onChanged: _isLoading ? null : _toggleSelectAll,
                        );
                      }
                      final file = _files[index - 1];
                      final isSelected = _selectedFiles.contains(file.name);
                      final isLoaded = _localKmlNames.contains(file.name);
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(file.name)),
                            if (isLoaded)
                              Row(
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                                  SizedBox(width: 4),
                                  Text('已加载', style: TextStyle(color: Colors.green, fontSize: 12)),
                                ],
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('大小: ${_formatFileSize(file.size)}'),
                            Text('修改时间: ${_formatDateTime(file.lastModified)}'),
                          ],
                        ),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedFiles.add(file.name);
                            } else {
                              _selectedFiles.remove(file.name);
                            }
                          });
                        },
                      );
                    },
                  ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV文件选择'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadFiles,
            tooltip: '刷新文件列表',
          ),
          if (_selectedFiles.isNotEmpty)
            TextButton(
              onPressed: _isLoading ? null : _downloadAndLoadFiles,
              child: const Text('下载选中文件'),
            ),
        ],
      ),
      body: _isDesktop
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: content,
              ),
            )
          : content,
    );
  }
} 