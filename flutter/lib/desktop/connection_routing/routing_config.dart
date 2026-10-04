import 'dart:convert';

const routingOption = 'mirra-id-routing-v1';
const routingUiEnabled = bool.fromEnvironment('MIRRA_ROUTING_UI');
const _defaultKey = 'QmfG5xMJbd52Bev1msSG8Vfe+RVRKXQD98NkQGc1gJg=';

class IdService {
  final String id;
  final String name;
  final String host;
  final String publicKey;

  const IdService(this.id, this.name, this.host, this.publicKey);

  factory IdService.fromJson(Map<String, dynamic> value) => IdService(
      value['id'] as String,
      value['name'] as String,
      value['host'] as String,
      value['public_key'] as String);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'host': host, 'public_key': publicKey};
}

class RoutingConfig {
  final bool enabled;
  final List<IdService> servers;
  final Map<String, String> deviceRoutes;

  RoutingConfig(
      {required this.enabled,
      required List<IdService> servers,
      required Map<String, String> deviceRoutes})
      : servers = List.unmodifiable(servers),
        deviceRoutes = Map.unmodifiable(deviceRoutes);

  factory RoutingConfig.defaults() =>
      RoutingConfig(enabled: true, servers: const [
        IdService('us', '美国', 'us.rustdesk.mirra-xr.com', _defaultKey),
        IdService('cn', '中国', 'rustdesk.mirra-xr.com', _defaultKey),
      ], deviceRoutes: {});

  factory RoutingConfig.decode(String value) {
    if (value.isEmpty) return RoutingConfig.defaults();
    final map = jsonDecode(value) as Map<String, dynamic>;
    if (map['version'] != 1 ||
        map.keys.any((key) => ![
              'version',
              'enabled',
              'servers',
              'device_routes'
            ].contains(key))) {
      throw const FormatException('不支持的连接路由配置版本');
    }
    final config = RoutingConfig(
        enabled: map['enabled'] as bool,
        servers: (map['servers'] as List)
            .map((s) => IdService.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        deviceRoutes: Map<String, String>.from(map['device_routes']));
    config.validate();
    return config;
  }

  RoutingConfig copyWith(
          {bool? enabled,
          List<IdService>? servers,
          Map<String, String>? deviceRoutes}) =>
      RoutingConfig(
          enabled: enabled ?? this.enabled,
          servers: servers ?? this.servers,
          deviceRoutes: deviceRoutes ?? this.deviceRoutes);

  String encode() => jsonEncode({
        'version': 1,
        'enabled': enabled,
        'servers': servers.map((s) => s.toJson()).toList(),
        'device_routes': deviceRoutes
      });

  void validate() {
    if (servers.isEmpty) throw const FormatException('至少保留一个 ID 服务');
    final ids = <String>{};
    final hosts = <String>{};
    for (final server in servers) {
      final parts = server.host.split('.');
      final validHost = server.host.length <= 253 &&
          parts.every((part) =>
              part.isNotEmpty &&
              part.length <= 63 &&
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                  .hasMatch(part));
      if (server.id.isEmpty ||
          server.name.trim().isEmpty ||
          !validHost ||
          !ids.add(server.id) ||
          !hosts.add(server.host.toLowerCase())) {
        throw const FormatException(
            '服务名称不能为空，地址需为唯一的主机名或 IPv4（不带端口或 https://）');
      }
      try {
        if (base64Decode(server.publicKey).length != 32) {
          throw const FormatException();
        }
      } catch (_) {
        throw const FormatException('公钥需为 Base64 编码的 32 字节服务器公钥');
      }
    }
    for (final route in deviceRoutes.entries) {
      if (!RegExp(r'^[0-9]+$').hasMatch(route.key) ||
          (route.value.isNotEmpty && !ids.contains(route.value))) {
        throw const FormatException('设备 ID 必须为数字，所选服务必须存在');
      }
    }
  }

  RoutingConfig withoutService(String id) {
    if (deviceRoutes.values.contains(id)) {
      throw const FormatException('此服务仍被设备使用，请先调整对应设备的路由');
    }
    final result = copyWith(servers: servers.where((s) => s.id != id).toList());
    result.validate();
    return result;
  }
}
