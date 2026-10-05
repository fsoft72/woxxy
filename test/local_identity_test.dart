import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/network_constants.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/services/network/send_service.dart';

void main() {
  test('an empty username falls back to the default name', () {
    expect(LocalIdentity(username: '').username, DEFAULT_USERNAME);
    expect(LocalIdentity().username, DEFAULT_USERNAME);

    final identity = LocalIdentity(username: 'alice');
    identity.username = '';
    expect(identity.username, DEFAULT_USERNAME);
  });

  test('services read the shared identity at use time, so no update fan-out is needed', () {
    final identity = LocalIdentity(ipAddress: '10.0.0.1');
    final sender = SendService(identity: identity);

    identity.ipAddress = '10.0.0.2';
    identity.username = 'bob';

    expect(sender.identity.ipAddress, '10.0.0.2');
    expect(sender.identity.username, 'bob');
  });
}
