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
  bool _closed = false;
  int _attempt = 0;

  Connection({
    required this.host,
    this.port = 8877,
    this.player = 1,
    this.maxPlayer = 2,
  });

  String get _url => 'ws://$host:$port';

  Future<void> connect() async {
    _closed = false;
    _set(ConnState.connecting);
    _open();
  }

  void _open() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      _channel!.sink.add(jsonEncode(HelloMessage(device: deviceLabel, player: player).toJson()));
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
        cancelOnError: true,
      );
      _set(ConnState.connected);
      _attempt = 0;
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

  void _sendPing(_) {
    if (state == ConnState.connected) {
      _channel?.sink.add(jsonEncode(PingMessage(DateTime.now().millisecondsSinceEpoch).toJson()));
    }
  }

  /// Send a single button transition. Callers should de-dupe with a held-state set.
  void input(String button, String down) {
    if (state != ConnState.connected) return;
    _channel?.sink.add(jsonEncode(InputMessage(player: player, button: button, state: down).toJson()));
  }

  void _onClosed() {
    if (_closed) return;
    _channel?.sink.close();
    _ping?.cancel();
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
    _reconnect?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
