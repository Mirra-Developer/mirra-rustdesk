import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'routing_config.dart';
import 'routing_store.dart';

class ConnectionRoutingPage extends StatefulWidget {
  const ConnectionRoutingPage({super.key});

  @override
  State<ConnectionRoutingPage> createState() => _ConnectionRoutingPageState();
}

class _ConnectionRoutingPageState extends State<ConnectionRoutingPage> {
  final _store = RoutingStore();
  RoutingConfig? _config;
  String? _error;
  bool _saving = false;
  final _localPeers = <String, String>{};

  @override
  void initState() {
    super.initState();
    try {
      _config = _store.load();
    } catch (error) {
      _error = _errorText(error);
    }
    _loadLocalPeers();
  }

  Future<void> _loadLocalPeers() async {
    try {
      final ids = await bind.mainGetFav();
      final peers = <String, String>{};
      for (final id in ids) {
        if (!RegExp(r'^[0-9]+$').hasMatch(id)) {
          continue;
        }
        final data =
            jsonDecode(bind.mainGetPeerSync(id: id)) as Map<String, dynamic>;
        final info = data['info'] as Map<String, dynamic>? ?? {};
        final options = data['options'] as Map<String, dynamic>? ?? {};
        final alias = options['alias'] as String? ?? '';
        peers[id] =
            alias.isNotEmpty ? alias : info['hostname'] as String? ?? id;
      }
      if (mounted) setState(() => _localPeers.addAll(peers));
    } catch (error) {
      if (mounted) setState(() => _error = '读取本机收藏失败：$error');
    }
  }

  Future<void> _save(RoutingConfig config) async {
    setState(() => _saving = true);
    try {
      await _store.save(config);
      if (mounted) {
        setState(() {
          _config = config;
          _error = null;
        });
        _notify('已保存，下一次连接生效');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notify(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Future<void> _editService([IdService? service]) async {
    final result = await showDialog<RoutingConfig>(
        context: context,
        builder: (context) =>
            _ServiceDialog(config: _config!, service: service));
    if (result != null && mounted) await _save(result);
  }

  Future<void> _deleteService(IdService service) async {
    RoutingConfig next;
    try {
      next = _config!.withoutService(service.id);
    } catch (e) {
      setState(() => _error = _errorText(e));
      _notify(_error!);
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('删除 ${service.name}？'),
                content: const Text('此操作只删除本机的连接服务配置。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (confirmed == true && mounted) await _save(next);
  }

  Future<void> _addDevice() async {
    String id = '';
    String? error;
    final result = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  title: const Text('添加设备路由'),
                  content: TextField(
                      autofocus: true,
                      onChanged: (value) => id = value.trim(),
                      decoration: InputDecoration(
                          labelText: '普通数字 ID', errorText: error)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    ElevatedButton(
                        onPressed: () {
                          if (!RegExp(r'^[0-9]+$').hasMatch(id)) {
                            setDialogState(() => error = '请输入普通数字 ID');
                            return;
                          }
                          Navigator.pop(context, id);
                        },
                        child: const Text('添加'))
                  ],
                )));
    if (result != null && mounted) {
      await _save(_config!.copyWith(deviceRoutes: {
        ..._config!.deviceRoutes,
        result: _config!.deviceRoutes[result] ?? ''
      }));
    }
  }

  Map<String, String> _deviceNames() {
    final names = {..._localPeers};
    for (final ab in gFFI.abModel.addressbooks.values) {
      for (final peer in ab.peers) {
        if (RegExp(r'^[0-9]+$').hasMatch(peer.id)) {
          names[peer.id] = peer.alias.isNotEmpty ? peer.alias : peer.hostname;
        }
      }
    }
    for (final id in _config!.deviceRoutes.keys) {
      names.putIfAbsent(id, () => id);
    }
    return names;
  }

  Widget _card(String title, Widget content) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            content
          ])));

  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 760,
          child: ListView(padding: const EdgeInsets.all(15), children: [
            if (_error != null)
              _card(
                  '提示',
                  SelectableText(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (_config != null) ...[
              _card(
                  '连接路由',
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('启用多 ID 服务路由'),
                            value: _config!.enabled,
                            onChanged: _saving
                                ? null
                                : (value) =>
                                    _save(_config!.copyWith(enabled: value))),
                        const Text(
                            '自动：查询所有已配置服务，连接唯一报告在线的服务。\n指定服务：直接使用所选服务，不自动切换。\n未单独指定的设备使用自动模式；关闭后使用原 Network 设置。'),
                        const SizedBox(height: 10),
                        const Text(
                            '启用时，连接需登录 Account，并沿用设备密码和现有服务端验证。更改在下一次连接生效。'),
                      ])),
              _card(
                  'ID 服务',
                  Column(children: [
                    for (final service in _config!.servers)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(service.name),
                          subtitle: SelectableText(service.host),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: '编辑服务',
                                onPressed: _saving
                                    ? null
                                    : () => _editService(service),
                                icon: const Icon(Icons.edit_outlined)),
                            IconButton(
                                tooltip: '删除服务',
                                onPressed: _saving
                                    ? null
                                    : () => _deleteService(service),
                                icon: const Icon(Icons.delete_outline)),
                          ])),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                            onPressed: _saving ? null : () => _editService(),
                            icon: const Icon(Icons.add),
                            label: const Text('添加 ID 服务'))),
                  ])),
              _card(
                  '设备路由',
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('显示已加载的地址簿、当前本机收藏和手动添加的 ID。选择仅保存本机。'),
                        const SizedBox(height: 12),
                        Obx(() {
                          final names = _deviceNames();
                          final ids = names.keys.toList()..sort();
                          if (ids.isEmpty) {
                            return const Text('暂无设备。登录并加载地址簿，或添加普通数字 ID。');
                          }
                          return Column(children: [
                            for (final id in ids)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 5),
                                  child: Row(children: [
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(names[id]!.isEmpty
                                              ? id
                                              : names[id]!),
                                          SelectableText(id),
                                        ])),
                                    SizedBox(
                                        width: 170,
                                        child: DropdownButtonFormField<String>(
                                            key: ValueKey(
                                                '$id-${_config!.deviceRoutes[id] ?? ''}'),
                                            value:
                                                _config!.deviceRoutes[id] ?? '',
                                            isExpanded: true,
                                            items: [
                                              const DropdownMenuItem(
                                                  value: '', child: Text('自动')),
                                              for (final s in _config!.servers)
                                                DropdownMenuItem(
                                                    value: s.id,
                                                    child: Text(s.name))
                                            ],
                                            onChanged: _saving
                                                ? null
                                                : (service) {
                                                    if (service != null) {
                                                      _save(_config!.copyWith(
                                                          deviceRoutes: {
                                                            ..._config!
                                                                .deviceRoutes,
                                                            id: service
                                                          }));
                                                    }
                                                  })),
                                    IconButton(
                                        tooltip: '清除本机路由规则',
                                        onPressed: _saving ||
                                                !_config!.deviceRoutes
                                                    .containsKey(id)
                                            ? null
                                            : () {
                                                final routes = {
                                                  ..._config!.deviceRoutes
                                                }..remove(id);
                                                _save(_config!.copyWith(
                                                    deviceRoutes: routes));
                                              },
                                        icon: const Icon(Icons.clear)),
                                  ]))
                          ]);
                        }),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            onPressed: _saving ? null : _addDevice,
                            icon: const Icon(Icons.add),
                            label: const Text('添加设备 ID')),
                      ])),
            ],
          ])));
}

class _ServiceDialog extends StatefulWidget {
  final RoutingConfig config;
  final IdService? service;
  const _ServiceDialog({required this.config, this.service});

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _host = TextEditingController(text: widget.service?.host ?? '');
  late final _key =
      TextEditingController(text: widget.service?.publicKey ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _key.dispose();
    super.dispose();
  }

  void _submit() {
    final service = widget.service;
    final replacement = IdService(
        service?.id ?? 's-${DateTime.now().microsecondsSinceEpoch}',
        _name.text.trim(),
        _host.text.trim(),
        _key.text.trim());
    final servers = [...widget.config.servers];
    if (service == null) {
      servers.add(replacement);
    } else {
      servers[servers.indexWhere((s) => s.id == service.id)] = replacement;
    }
    final next = widget.config.copyWith(servers: servers);
    try {
      next.validate();
      Navigator.pop(context, next);
    } catch (e) {
      setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.service == null ? '添加 ID 服务' : '编辑 ID 服务'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名称')),
              TextField(
                  controller: _host,
                  decoration: const InputDecoration(
                      labelText: 'ID 服务地址', hintText: '主机名或 IPv4，不带端口')),
              TextField(
                  controller: _key,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '服务器公钥')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(onPressed: _submit, child: const Text('保存')),
        ],
      );
}

String _errorText(Object error) => error is FormatException
    ? error.message
    : error is StateError
        ? '${error.message}'
        : '$error';
