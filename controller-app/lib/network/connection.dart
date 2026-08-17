/// WebSocket client with automatic reconnect + exponential backoff.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/protocol.dart';

enum ConnState { disconnected, connecting, connected, reconnecting }

/// MethodChannel to the native ControllerService (keeps the app alive while playing).
const MethodChannel _serviceChannel = MethodChannel('retrolan/service');
/// MethodChannel to the native file picker + chunked reader (no OOM on big files).
const MethodChannel _fileChannel = MethodChannel('retrolan/filepicker');

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
  DateTime _lastPongAt = DateTime.now(); // dead-link detection

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
      if (m is PongMessage) { latencyMs = DateTime.now().millisecondsSinceEpoch - m.ts; _lastPongAt = DateTime.now(); }
      if (m is StateMessage) {
        // 'resync' = the TV's emulator relay restarted and cleared the core's button
        // state — the UI must re-send whatever it is still holding.
        if (m.status == 'resync') onResync?.call();
      }
      notifyListeners();
    } catch (_) {/* ignore malformed */}
  }

  /// Called when the TV asks us to re-send held buttons (relay restart).
  VoidCallback? onResync;

  void _sendPing(Timer t) {
    if (state == ConnState.connected) {
      _channel?.sink.add(jsonEncode(PingMessage(DateTime.now().millisecondsSinceEpoch).toJson()));
      // Dead-link detection: if the TV hasn't ponged for 5s, the socket is silently
      // dead (Wi-Fi blip / TV hiccup). Force a clean reconnect instead of freezing.
      if (DateTime.now().difference(_lastPongAt).inSeconds > 5) {
        _onClosed();
      }
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

  /// Stream a ROM file (your own local file) to the TV over Wi-Fi in 256KB chunks
  /// so huge files (ISO/CHD/PSX images) never load into phone RAM — no OOM crash.
  /// `pick` is the result of the native 'pickFile' call: {name, size, uri}.
  Future<bool> sendRomStream(Map<String, dynamic> pick, {void Function(int, int)? onProgress}) async {
    if (state != ConnState.connected) return false;
    final ws = _channel;
    if (ws == null) return false;
    final name = pick['name'] as String? ?? 'game';
    final size = (pick['size'] as num?)?.toInt() ?? 0;
    final uri = pick['uri'] as String? ?? '';
    ws.sink.add(jsonEncode({'type': 'rom_upload', 'name': name}));
    const chunk = 256 * 1024;
    var offset = 0;
    var sent = 0;
    while (true) {
      // Pull one chunk from native (content URI) — never more than 256KB in RAM.
      // Android returns List<int>; iOS returns Uint8List — handle both.
      final Object? raw;
      try {
        raw = await _fileChannel.invokeMethod<Object?>('readChunk', {
          'uri': uri, 'offset': offset, 'length': chunk,
        });
      } catch (_) { break; }
      if (raw == null) break;
      final Uint8List bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List) {
        bytes = Uint8List.fromList(raw.cast<int>());
      } else {
        break;
      }
      if (bytes.isEmpty) break;
      ws.sink.add(bytes);
      sent += bytes.length;
      onProgress?.call(sent, size);
      if (bytes.length < chunk) break; // last chunk
      offset += chunk;
      // Let the socket breathe between chunks (big files, slow Wi-Fi).
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    ws.sink.add(jsonEncode({'type': 'rom_end', 'name': name}));
    return sent > 0;
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

  void _set(ConnState s) {
    final prev = state;
    state = s;
    if (s == ConnState.connected && prev != ConnState.connected) {
      // Connected: keep the app alive in the background (foreground service).
      try { _serviceChannel.invokeMethod('startService'); } catch (_) {}
    } else if (s != ConnState.connected && prev == ConnState.connected) {
      try { _serviceChannel.invokeMethod('stopService'); } catch (_) {}
    }
    notifyListeners();
  }

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
