import 'package:flutter/material.dart';

import '../models/map_config.dart';
import '../models/tile_server.dart';

/// 底图供应商选择器。返回用户选中的下标；取消返回 null。
Future<int?> showTileServerSelector(
  BuildContext context, {
  required List<TileServer> servers,
  required int currentIndex,
  required Future<void> Function() onRetest,
}) {
  final visible = <int>[
    for (var i = 0; i < servers.length; i++)
      if (servers[i].visible) i,
  ];

  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选择地图供应商'),
      content: SizedBox(
        width: 500,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final index = visible[i];
            final server = servers[index];
            return ListTile(
              leading: _statusDot(server.status),
              title: Text(server.name),
              subtitle: Text(
                server.requiresTiandituKey && !MapConfig.isTiandituKeyValid
                    ? '${server.attribution} · 未配置密钥'
                    : server.attribution,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index == currentIndex)
                    const Icon(Icons.check, color: Colors.blue),
                ],
              ),
              onTap: () => Navigator.of(context).pop(index),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: onRetest,
          child: const Text('重新测试'),
        ),
      ],
    ),
  );
}

/// 底图供应商开关设置（哪些出现在选择列表里）。保存后通过 [onApply] 回传。
Future<void> showTileServerSettings(
  BuildContext context, {
  required List<TileServer> servers,
  required void Function(List<bool> visibility) onApply,
  required Future<void> Function(int index) onTestOne,
  required Future<void> Function() onTestAll,
}) {
  // 本地副本，取消则不生效。
  final draft = servers.map((s) => s.visible).toList();
  // 探测状态也放在本地，刷新后即时反映。
  final statuses = servers.map((s) => s.status).toList();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('地图供应商设置'),
        content: SizedBox(
          width: 500,
          height: 420,
          child: Column(
            children: [
              const Text(
                '勾选要在地图供应商选择界面中显示的底图：',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: servers.length,
                  itemBuilder: (context, i) {
                    final server = servers[i];
                    return CheckboxListTile(
                      dense: true,
                      title: Text(server.name),
                      subtitle: Row(
                        children: [
                          _statusDot(statuses[i]),
                          const SizedBox(width: 6),
                          Text(
                            _statusText(statuses[i]),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (server.requiresTiandituKey) ...[
                            const SizedBox(width: 6),
                            Text(
                              MapConfig.isTiandituKeyValid ? '· 已配密钥' : '· 缺密钥',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      value: draft[i],
                      onChanged: (v) => setLocal(() => draft[i] = v ?? true),
                      secondary: IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: '测试连接',
                        onPressed: () async {
                          setLocal(() => statuses[i] = TileServerStatus.testing);
                          await onTestOne(i);
                          if (dialogContext.mounted) {
                            setLocal(() => statuses[i] = servers[i].status);
                          }
                        },
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
            onPressed: () => setLocal(
              () => draft.fillRange(0, draft.length, true),
            ),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: () async {
              await onTestAll();
              if (dialogContext.mounted) {
                for (var i = 0; i < statuses.length; i++) {
                  statuses[i] = servers[i].status;
                }
                setLocal(() {});
              }
            },
            child: const Text('测试全部'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onApply(draft);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

/// 天地图 API Key 设置。
Future<void> showTiandituSettings(BuildContext context) {
  final controller = TextEditingController(text: MapConfig.tiandituApiKey);
  var isValid = MapConfig.isTiandituKeyValid;
  var saving = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('天地图 API 密钥'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('当前状态：'),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isValid ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isValid ? '已配置' : '未配置',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '天地图三款底图需要密钥才能出图。申请地址：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 2),
            const SelectableText(
              'https://console.tianditu.gov.cn/api/key',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API 密钥',
                hintText: '32 位密钥',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setLocal(() => saving = true);
                    await MapConfig.setTiandituApiKey(controller.text.trim());
                    if (!dialogContext.mounted) return;
                    setLocal(() {
                      isValid = MapConfig.isTiandituKeyValid;
                      saving = false;
                    });
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('天地图密钥已保存')),
                    );
                    Navigator.of(dialogContext).pop();
                  },
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}

Widget _statusDot(TileServerStatus status) {
  switch (status) {
    case TileServerStatus.available:
      return _dot(Colors.green);
    case TileServerStatus.unavailable:
      return _dot(Colors.red);
    case TileServerStatus.testing:
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    case TileServerStatus.unknown:
      return _dot(Colors.grey);
  }
}

Widget _dot(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

String _statusText(TileServerStatus status) {
  switch (status) {
    case TileServerStatus.available:
      return '可用';
    case TileServerStatus.unavailable:
      return '不可用';
    case TileServerStatus.testing:
      return '测试中';
    case TileServerStatus.unknown:
      return '未测试';
  }
}
