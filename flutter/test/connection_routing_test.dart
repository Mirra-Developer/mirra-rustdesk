import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/connection_routing/routing_config.dart';

void main() {
  test('manual assignments persist through service rename and reorder', () {
    final config = RoutingConfig.defaults();
    final china = config.servers[1];
    final changed = config.copyWith(servers: [
      IdService(china.id, 'China office', china.host, china.publicKey),
      config.servers[0],
    ], deviceRoutes: {
      '123': 'cn',
      '456': ''
    });
    final loaded = RoutingConfig.decode(changed.encode());
    expect(loaded.deviceRoutes['123'], 'cn');
    expect(loaded.deviceRoutes['456'], '');
    expect(loaded.servers.first.name, 'China office');
    expect(loaded.encode(), changed.encode());
    expect(() => loaded.withoutService('cn'), throwsFormatException);
  });

  test('service validation rejects duplicate addresses and invalid public keys',
      () {
    final config = RoutingConfig.defaults();
    for (final service in [
      IdService('third', 'Third', config.servers[0].host.toUpperCase(),
          config.servers[0].publicKey),
      const IdService('third', 'Third', 'https://example.com', 'bad'),
      const IdService('third', 'Third', 'example.com', 'bad'),
    ]) {
      expect(
          () =>
              config.copyWith(servers: [...config.servers, service]).validate(),
          throwsFormatException);
    }
    expect(() => RoutingConfig.decode('broken'), throwsFormatException);
    expect(() => config.copyWith(deviceRoutes: {'123': 'missing'}).validate(),
        throwsFormatException);
  });

  test(
      'third region and feature disabled survive persistence without credentials',
      () {
    final config = RoutingConfig.defaults();
    final third = IdService(
        'third', 'Third', 'third.example.com', config.servers[0].publicKey);
    final changed = config.copyWith(
        enabled: false,
        servers: [...config.servers, third],
        deviceRoutes: {'999': 'third'});
    final loaded = RoutingConfig.decode(changed.encode());
    expect(loaded.enabled, isFalse);
    expect(loaded.servers.length, 3);
    expect(loaded.deviceRoutes['999'], 'third');
    expect(loaded.encode(), isNot(contains('access_token')));
    expect(loaded.encode(), isNot(contains('password')));
  });
}
