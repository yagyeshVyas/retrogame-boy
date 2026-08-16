/// WebSocket client with automatic reconnect + exponential backoff.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/protocol.dart';

enum ConnState { disconnected, connecting, connected, reconnecting }

class Connection extends ChangeNotifier {
  ConnState state = ConnState.disconnected;
  String? tvName;
  List<String> cores = const [];
  int latencyMs = 0;
  String deviceLabel = 'Controller';

  final int player;
  final String host;
  final int port;
  final int maxPlayer;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Timer? _ping;
  bool _closed = false;       // true after dispose — never reconnect
  bool _handlingClose = false; // guard: onError + onDone fire for the SAME close
  int _attempt = 0;

  Connection({
    required this.host,
    this.port = 8877,
    this.player = 1,
    this.maxPlayer = 2,
  });

  String get _url => 'ws://$host:$port';

  Future<void> connect() async {
    if (_closed) return; // disposed — never revive
    _handlingClose = false;
    _set(ConnState.connecting);
    _open();
  }

  void _open() {
    try {
      final ch = WebSocketChannel.connect(Uri.parse(_url));
      _channel = ch;
      ch.sink.add(jsonEncode(HelloMessage(device: deviceLabel, player: player).toJson()));
      _sub = ch.stream.listen(
        _onData,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
        cancelOnError: true,
      );
      _attempt = 0;
      _set(ConnState.connected);
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 1), _sendPing);
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      final m = decodeMessage(j);
      if (m is HelloAckMessage) { tvName = m.name; cores = m.cores; }
      if (m is PongMessage) { latencyMs = DateTime.now().millisecondsSinceEpoch - m.ts; }
      if (m is StateMessage) { /* status pill could reflect pause */ }
      notifyListeners();
    } catch (_) {/* ignore malformed */}
  }

  void _sendPing(Timer t) {
    if (state == ConnState.connected) {
      _channel?.sink.add(jsonEncode(PingMessage(DateTime.now().millisecondsSinceEpoch).toJson()));
    }
  }

  /// Send a single button transition. Callers should de-dupe with a held-state set.
  void input(String button, String down) {
    if (state != ConnState.connected) return;
    _channel?.sink.add(jsonEncode(InputMessage(player: player, button: button, state: down).toJson()));
  }

  /// Send a control command to the TV: 'back' (exit game) or 'close' (stop + exit).
  void control(String action) {
    if (state != ConnState.connected) return;
    _channel?.sink.add(jsonEncode({'type': 'control', 'action': action}));
  }

  /// Send a ROM file (your own local file) to the TV over Wi-Fi so the TV plays it.
  /// Header -> binary bytes -> end marker. Returns true if the transfer was sent.
  bool sendRom(String fileName, List<int> bytes) {
    if (state != ConnState.connected) return false;
    final ws = _channel;
    if (ws == null) return false;
    // Header declares the filename; TV reads the following binary frames as the ROM.
    ws.sink.add(jsonEncode({
      'type': 'rom_upload',
      'name': fileName,
    }));
    // Send the file bytes as raw binary (split into chunks for large ROMs).
    const chunk = 64 * 1024;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
      ws.sink.add(bytes.sublist(i, end));
    }
    // Signal completion; TV saves + plays.
    ws.sink.add(jsonEncode({'type': 'rom_end', 'name': fileName}));
    return true;
  }

  /// Handle a socket close exactly ONCE (onError and onDone both fire for the
  /// same close — without this guard we'd loop and spawn duplicate timers).
  void _onClosed() {
    if (_closed) return;
    if (_handlingClose) return;
    _handlingClose = true;
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _set(state == ConnState.connected ? ConnState.reconnecting : ConnState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    if (_closed) return;
    final delay = Duration(milliseconds: 400 * (1 << _attempt).clamp(1, 6)); // backoff 400..25.6s
    _attempt++;
    _reconnect = Timer(delay, connect);
  }

  void _set(ConnState s) { state = s; notifyListeners(); }

  @override
  void dispose() {
    _closed = true;
    _handlingClose = true;
    _reconnect?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
