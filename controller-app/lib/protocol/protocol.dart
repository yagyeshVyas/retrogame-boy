/// RetroLAN wire protocol v1 — see /protocol/PROTOCOL.md
/// Minimal, change-only JSON messages over WebSocket.
library;

/// Every button the protocol understands.
const List<String> kButtons = [
  'dpad_up', 'dpad_down', 'dpad_left', 'dpad_right',
  'a', 'b', 'x', 'y', 'start', 'select', 'l', 'r',
];

/// A single decoded protocol message.
sealed class ProtoMessage {
  const ProtoMessage();
  Map<String, dynamic> toJson();
}

/// Controller -> TV: identify + choose a player slot.
class HelloMessage extends ProtoMessage {
  final String device;
  final String role;
  final int player;
  const HelloMessage({required this.device, required this.player, this.role = 'controller'});
  @override Map<String, dynamic> toJson() => {'type': 'hello', 'device': device, 'role': role, 'player': player};
}

/// TV -> Controller: acknowledge + list available cores.
class HelloAckMessage extends ProtoMessage {
  final String name;
  final List<String> cores;
  const HelloAckMessage({required this.name, required this.cores});
  factory HelloAckMessage.fromJson(Map<String, dynamic> j) =>
      HelloAckMessage(name: j['name'] as String, cores: (j['cores'] as List).cast<String>());
  @override Map<String, dynamic> toJson() => {'type': 'hello_ack', 'name': name, 'cores': cores};
}

/// Controller -> TV: a single button transition (down/up).
class InputMessage extends ProtoMessage {
  final int player;
  final String button;
  final String state; // 'down' | 'up'
  const InputMessage({required this.player, required this.button, required this.state});
  @override Map<String, dynamic> toJson() => {'type': 'input', 'player': player, 'button': button, 'state': state};
}

/// Either direction: latency probe.
class PingMessage extends ProtoMessage {
  final int ts;
  const PingMessage(this.ts);
  @override Map<String, dynamic> toJson() => {'type': 'ping', 'ts': ts};
}
class PongMessage extends ProtoMessage {
  final int ts;
  const PongMessage(this.ts);
  factory PongMessage.fromJson(Map<String, dynamic> j) => PongMessage(j['ts'] as int);
  @override Map<String, dynamic> toJson() => {'type': 'pong', 'ts': ts};
}

/// TV -> Controller: informational state (idle/loading/running/paused).
class StateMessage extends ProtoMessage {
  final String status;
  final String? rom;
  final bool paused;
  final int fps;
  const StateMessage({required this.status, this.rom, required this.paused, required this.fps});
  factory StateMessage.fromJson(Map<String, dynamic> j) => StateMessage(
        status: j['status'] as String,
        rom: j['rom'] as String?,
        paused: j['paused'] as bool,
        fps: (j['fps'] as num?)?.toInt() ?? 0,
      );
  @override Map<String, dynamic> toJson() => {'type': 'state', 'status': status, 'rom': rom, 'paused': paused, 'fps': fps};
}

/// Either direction: error.
class ErrorMessage extends ProtoMessage {
  final String code;
  final String message;
  const ErrorMessage({required this.code, required this.message});
  @override Map<String, dynamic> toJson() => {'type': 'error', 'code': code, 'message': message};
}

/// Decode an arbitrary JSON object into the union.
ProtoMessage? decodeMessage(Map<String, dynamic> j) {
  switch (j['type'] as String?) {
    case 'hello_ack': return HelloAckMessage.fromJson(j);
    case 'pong': return PongMessage.fromJson(j);
    case 'state': return StateMessage.fromJson(j);
    default: return null; // hello/input/ping/error are controller->TV or handled elsewhere
  }
}
