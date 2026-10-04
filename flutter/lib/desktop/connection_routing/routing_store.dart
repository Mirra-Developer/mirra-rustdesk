import '../../models/platform_model.dart';
import 'routing_config.dart';

class RoutingStore {
  RoutingConfig load() =>
      RoutingConfig.decode(bind.mainGetLocalOption(key: routingOption));

  Future<void> save(RoutingConfig config) async {
    config.validate();
    final value = config.encode();
    await bind.mainSetLocalOption(key: routingOption, value: value);
    if (bind.mainGetLocalOption(key: routingOption) != value) {
      throw StateError('连接路由配置未保存');
    }
  }
}
