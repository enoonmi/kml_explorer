import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/map_config.dart';
import '../models/tile_server.dart';

/// 瓦片供应商健康探测。
///
/// 把网络请求从 UI 状态里抽出来，便于单测与复用。
class TileServerProbe {
  TileServerProbe({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  /// 探测单个供应商是否可用。
  ///
  /// 把 URL 模板里的 `{z}/{x}/{y}/{s}` 换成一组固定值取一张瓦片，
  /// 返回 200 视为可用。
  Future<TileProbeResult> probe(TileServer server) async {
    try {
      var testUrl = server.url
          .replaceAll('{z}', '10')
          .replaceAll('{x}', '512')
          .replaceAll('{y}', '256');
      if (server.subdomains != null && server.subdomains!.isNotEmpty) {
        testUrl = testUrl.replaceAll('{s}', server.subdomains!.first);
      }
      // 天地图必须带合法 Key，否则必然 403。
      if (server.requiresTiandituKey) {
        if (!MapConfig.isTiandituKeyValid) {
          return const TileProbeResult(
            available: false,
            errorMessage: '未配置天地图 API Key',
          );
        }
        testUrl = MapConfig.getTiandituUrl(testUrl);
      }

      final response = await _client.get(
        Uri.parse(testUrl),
        headers: const {
          'User-Agent': 'KML Explorer/1.0',
          'Accept': 'image/png,image/*,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return const TileProbeResult(available: true);
      }
      return TileProbeResult(
        available: false,
        errorMessage: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      return TileProbeResult(available: false, errorMessage: e.toString());
    }
  }

  /// 顺序探测一组供应商（带节流，避免同时打太多请求）。
  Future<List<TileProbeResult>> probeAll(List<TileServer> servers) async {
    final results = <TileProbeResult>[];
    for (final server in servers) {
      results.add(await probe(server));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return results;
  }

  /// 轻量网络连通性探测。
  ///
  /// 原先打 httpbin.org，境外站点在国内常不可达；改为探测已选供应商
  /// 是否至少有一个能出图，语义更贴近真实需求。
  Future<bool> hasNetwork() async {
    try {
      final response = await _client
          .get(Uri.parse('https://tile.openstreetmap.org/10/512/256.png'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('网络探测失败: $e');
      return false;
    }
  }
}

@immutable
class TileProbeResult {
  const TileProbeResult({required this.available, this.errorMessage});

  final bool available;
  final String? errorMessage;
}
