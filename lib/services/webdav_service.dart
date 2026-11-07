import 'dart:io';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class WebDavFile {
  final String name;
  final String path;
  final int size;
  final DateTime lastModified;
  final bool isDirectory;

  WebDavFile({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.isDirectory,
  });
}

class WebDavService {
  static WebDavService? _instance;
  static WebDavService get instance => _instance ??= WebDavService._();

  WebDavService._();

  String _url = '';
  String _username = '';
  String _password = '';
  String _path = '/kml_files';
  bool _isEnabled = false;
  webdav.Client? _client;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('webdav_enabled') ?? false;
    
    if (_isEnabled) {
      _url = prefs.getString('webdav_url') ?? '';
      _username = prefs.getString('webdav_username') ?? '';
      _password = prefs.getString('webdav_password') ?? '';
      _path = prefs.getString('webdav_path') ?? '/kml_files';
      
      if (_url.isNotEmpty && _username.isNotEmpty) {
        try {
          _client = webdav.newClient(
            _url,
            user: _username,
            password: _password,
          );
          debugPrint('WebDAV客户端初始化成功');
        } catch (e) {
          debugPrint('WebDAV客户端初始化失败: $e');
          _client = null;
        }
      }
    }
  }

  bool get isEnabled => _isEnabled;
  webdav.Client? get client => _client;

  Future<bool> uploadFile(File file, String fileName) async {
    if (!_isEnabled || _client == null) return false;

    try {
      final remotePath = path.join(_path, fileName).replaceAll('\\', '/');
      
      // 检查文件是否已存在
      final exists = await _exists(remotePath);
      if (exists) {
        debugPrint('WebDAV文件已存在: $remotePath');
        return false;
      }

      // 确保目录存在
      await _ensureDirectoryExists(_path);

      // 上传文件 - 使用writeFromFile方法，参数是本地文件路径和远程文件路径
      await _client!.writeFromFile(
        file.path, // 本地文件路径
        remotePath, // 远程文件路径
      );
      
      debugPrint('WebDAV文件上传成功: $remotePath');
      return true;
    } catch (e) {
      debugPrint('WebDAV文件上传失败: $e');
      return false;
    }
  }

  Future<List<WebDavFile>> listFiles() async {
    if (!_isEnabled || _client == null) return [];

    try {
      final files = await _client!.readDir(_path);
      final webDavFiles = <WebDavFile>[];
      
      for (final file in files) {
        final fileName = file.name ?? '';
        if (fileName.toLowerCase().endsWith('.kml')) {
          webDavFiles.add(WebDavFile(
            name: fileName,
            path: file.path ?? '',
            size: file.size ?? 0,
            // 原先这里写死 DateTime.now()，导致“保留最新”永远无从比较。
            lastModified: file.mTime?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
            isDirectory: file.isDir ?? false,
          ));
        }
      }
      
      return webDavFiles;
    } catch (e) {
      debugPrint('WebDAV列出文件失败: $e');
      return [];
    }
  }

  Future<File?> downloadFile(String fileName) async {
    if (!_isEnabled || _client == null) return null;

    try {
      final remotePath = path.join(_path, fileName).replaceAll('\\', '/');
      
      // 创建临时本地文件路径
      final localDir = Directory.systemTemp.createTempSync('kml_explorer');
      final localFilePath = '${localDir.path}/$fileName';
      
      // 使用read2File方法下载文件到本地
      await _client!.read2File(remotePath, localFilePath);
      
      final localFile = File(localFilePath);
      if (await localFile.exists()) {
        debugPrint('WebDAV文件下载成功: $fileName');
        return localFile;
      } else {
        debugPrint('WebDAV文件下载失败: 文件不存在');
        return null;
      }
    } catch (e) {
      debugPrint('WebDAV文件下载失败: $e');
      return null;
    }
  }

  Future<bool> _exists(String remotePath) async {
    try {
      // 只读一次目录，原先连续调了两次 readDir，多一次往返。
      final files = await _client!.readDir(path.dirname(remotePath));
      final fileName = path.basename(remotePath);
      return files.any((file) => file.name == fileName);
    } catch (e) {
      return false;
    }
  }

  Future<void> _ensureDirectoryExists(String dirPath) async {
    if (!_isEnabled || _client == null) return;

    try {
      await _client!.readDir(dirPath);
      // 目录已存在
    } catch (e) {
      // 目录不存在，创建它
      try {
        await _client!.mkdirAll(dirPath); // 使用mkdirAll递归创建目录
        debugPrint('WebDAV目录创建成功: $dirPath');
      } catch (e) {
        debugPrint('WebDAV目录创建失败: $e');
      }
    }
  }

  Future<void> deleteFile(String fileName) async {
    if (!_isEnabled || _client == null) return;

    try {
      final remotePath = path.join(_path, fileName).replaceAll('\\', '/');
      // 使用remove方法删除文件
      await _client!.remove(remotePath);
      debugPrint('WebDAV文件删除成功: $fileName');
    } catch (e) {
      debugPrint('WebDAV文件删除失败: $e');
    }
  }

  Future<bool> ping() async {
    if (!_isEnabled || _client == null) return false;

    try {
      // 使用ping方法测试连接
      await _client!.ping();
      return true;
    } catch (e) {
      debugPrint('WebDAV连接测试失败: $e');
      return false;
    }
  }

  // 获取详细的连接状态信息
  Future<Map<String, dynamic>> getConnectionStatus() async {
    if (!_isEnabled) {
      return {
        'enabled': false,
        'message': 'WebDAV未启用',
      };
    }

    if (_client == null) {
      return {
        'enabled': true,
        'connected': false,
        'message': 'WebDAV客户端未初始化',
        'url': _url,
        'username': _username,
      };
    }

    try {
      final success = await ping();
      return {
        'enabled': true,
        'connected': success,
        'message': success ? '连接正常' : '连接失败',
        'url': _url,
        'username': _username,
        'path': _path,
      };
    } catch (e) {
      return {
        'enabled': true,
        'connected': false,
        'message': '连接错误: $e',
        'url': _url,
        'username': _username,
        'path': _path,
      };
    }
  }

  // 新增：检查并清理重复文件
  Future<List<String>> findDuplicateFiles() async {
    if (!_isEnabled || _client == null) return [];

    try {
      final files = await listFiles();
      final Map<String, List<String>> fileGroups = {};
      
      // 按文件名分组（去除前缀）
      for (final file in files) {
        final baseName = _extractBaseFileName(file.name);
        if (!fileGroups.containsKey(baseName)) {
          fileGroups[baseName] = [];
        }
        fileGroups[baseName]!.add(file.name);
      }
      
      // 找出有重复的文件组
      final duplicates = <String>[];
      for (final entry in fileGroups.entries) {
        if (entry.value.length > 1) {
          duplicates.addAll(entry.value);
        }
      }
      
      return duplicates;
    } catch (e) {
      debugPrint('查找重复文件失败: $e');
      return [];
    }
  }

  // 新增：提取基础文件名（去除前缀）
  String _extractBaseFileName(String fileName) {
    // 移除常见的临时文件前缀
    final patterns = [
      RegExp(r'^kml_explorer[a-f0-9]+_'), // kml_explorer143f5f95_
      RegExp(r'^temp_'),
      RegExp(r'^tmp_'),
    ];
    
    String result = fileName;
    for (final pattern in patterns) {
      result = result.replaceFirst(pattern, '');
    }
    
    return result;
  }

  // 新增：清理重复文件，保留最新的一个
  Future<bool> cleanupDuplicateFiles() async {
    if (!_isEnabled || _client == null) return false;

    try {
      final files = await listFiles();
      final Map<String, List<WebDavFile>> fileGroups = {};
      
      // 按基础文件名分组
      for (final file in files) {
        final baseName = _extractBaseFileName(file.name);
        if (!fileGroups.containsKey(baseName)) {
          fileGroups[baseName] = [];
        }
        fileGroups[baseName]!.add(file);
      }
      
      int deletedCount = 0;
      
      // 处理每个重复文件组
      for (final entry in fileGroups.entries) {
        final group = entry.value;
        if (group.length > 1) {
          // 按修改时间排序，保留最新的
          group.sort((a, b) => b.lastModified.compareTo(a.lastModified));
          
          // 删除除最新文件外的所有文件
          for (int i = 1; i < group.length; i++) {
            await deleteFile(group[i].name);
            deletedCount++;
            debugPrint('删除重复文件: ${group[i].name}');
          }
        }
      }
      
      debugPrint('清理完成，删除了 $deletedCount 个重复文件');
      return true;
    } catch (e) {
      debugPrint('清理重复文件失败: $e');
      return false;
    }
  }
} 