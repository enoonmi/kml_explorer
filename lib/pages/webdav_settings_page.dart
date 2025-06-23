import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/webdav_service.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathController = TextEditingController();
  bool _isEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isEnabled = prefs.getBool('webdav_enabled') ?? false;
      _urlController.text = prefs.getString('webdav_url') ?? '';
      _usernameController.text = prefs.getString('webdav_username') ?? '';
      _passwordController.text = prefs.getString('webdav_password') ?? '';
      _pathController.text = prefs.getString('webdav_path') ?? '/kml_files';
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('webdav_enabled', _isEnabled);
      await prefs.setString('webdav_url', _urlController.text.trim());
      await prefs.setString('webdav_username', _usernameController.text.trim());
      await prefs.setString('webdav_password', _passwordController.text);
      await prefs.setString('webdav_path', _pathController.text.trim());

      // 重新初始化WebDAV服务
      await WebDavService.instance.initialize();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WebDAV设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await WebDavService.instance.getConnectionStatus();
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('WebDAV连接状态'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('启用状态: ${status['enabled'] ? '是' : '否'}'),
                if (status['enabled']) ...[
                  Text('连接状态: ${status['connected'] ? '正常' : '失败'}'),
                  Text('服务器URL: ${status['url']}'),
                  Text('用户名: ${status['username']}'),
                  Text('存储路径: ${status['path']}'),
                  const SizedBox(height: 8),
                  Text('详细信息: ${status['message']}'),
                ],
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WebDAV连接测试失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 新增：清理重复文件
  Future<void> _cleanupDuplicateFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await WebDavService.instance.cleanupDuplicateFiles();
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('重复文件清理完成')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('清理重复文件失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理重复文件时出错: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV设置'),
        actions: [
          if (_isEnabled) ...[
            TextButton(
              onPressed: _isLoading ? null : _cleanupDuplicateFiles,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('清理重复'),
            ),
            TextButton(
              onPressed: _isLoading ? null : _testConnection,
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('测试连接'),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 启用开关
            SwitchListTile(
              title: const Text('启用WebDAV'),
              subtitle: const Text('将KML文件同步到WebDAV服务器'),
              value: _isEnabled,
              onChanged: (value) {
                setState(() {
                  _isEnabled = value;
                });
              },
            ),
            const SizedBox(height: 16),

            if (_isEnabled) ...[
              // 服务器URL
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'WebDAV服务器URL',
                  hintText: 'https://your-webdav-server.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 用户名
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 密码
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 路径
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'KML文件存储路径',
                  hintText: '/kml_files',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存设置'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 