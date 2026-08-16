import 'package:flutter_test/flutter_test.dart';
import 'package:retrolan_controller/protocol/protocol.dart';

void main() {
  test('protocol input message serializes correctly', () {
    const m = InputMessage(player: 1, button: 'a', state: 'down');
    expect(m.toJson(), {'type': 'input', 'player': 1, 'button': 'a', 'state': 'down'});
  });

  test('hello message serializes with player', () {
    const m = HelloMessage(device: 'Test', player: 2);
    expect(m.toJson()['player'], 2);
    expect(m.toJson()['role'], 'controller');
  });

  test('pong decode', () {
    final m = PongMessage.fromJson({'ts': 1234});
    expect(m.ts, 1234);
  });
}
