import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show kBg, kPurple, kCyan, kGreen, kAmber, kInk, kMuted;
import '../network/connection.dart';

/// The retro-arcade gamepad: D-pad (cyan) bottom-left, A/B/X/Y (purple) bottom-right,
/// Start/Select pills, L/R shoulders. Soft glow on press, translucent resting state.
class GamepadScreen extends StatefulWidget {
  final String host;
  final int port;
  final int player;
  const GamepadScreen({super.key, required this.host, this.port = 8877, this.player = 1});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  late final Connection _conn;
  final Set<String> _held = {}; // dedupe: avoid re-sending down for a held button
  bool _abSwap = false;         // swap A<->B (NES: jump is usually B)

  @override
  void initState() {
    super.initState();
    _conn = Connection(host: widget.host, port: widget.port, player: widget.player)
      ..deviceLabel = 'FlutterController-${widget.player}'
      ..addListener(() => setState(() {}));
    _conn.connect();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _conn.dispose();
    super.dispose();
  }

  void _press(String button, bool down) {
    HapticFeedback.lightImpact(); // haptic on every press
    // A/B swap for games where jump is on B (NES convention) — remap before sending.
    if (_abSwap) {
      if (button == 'a') button = 'b';
      else if (button == 'b') button = 'a';
    }
    if (down == _held.contains(button)) return; // no change -> skip
    setState(() { down ? _held.add(button) : _held.remove(button); });
    _conn.input(button, down ? 'down' : 'up');
  }

  /// Pick a local ROM on the phone (via native Android file picker) and send it to
  /// the TV over Wi-Fi to play. Uses a MethodChannel to the host MainActivity, so no
  /// third-party picker plugin is needed.
  Future<void> _sendRom() async {
    if (_conn.state != ConnState.connected) return;
    const channel = MethodChannel('retrolan/filepicker');
    try {
      final Map<dynamic, dynamic>? picked =
          await channel.invokeMethod('pickFile') as Map<dynamic, dynamic>?;
      if (picked == null || picked.isEmpty) return; // user cancelled
      final name = picked['name'] as String;
      final bytes = (picked['bytes'] as List<dynamic>).cast<int>();
      final ok = _conn.sendRom(name, bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Sending $name to TV…' : 'Not connected to TV')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')));
    }
  }

  String get _statusText {
    switch (_conn.state) {
      case ConnState.connected: return _conn.tvName ?? 'Connected';
      case ConnState.connecting: return 'Connecting…';
      case ConnState.reconnecting: return 'Reconnecting…';
      case ConnState.disconnected: return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _conn.state == ConnState.connected;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          // Status pill: TV name + live latency + send-ROM action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _pill(icon: Icons.circle, color: connected ? kGreen : kAmber, text: _statusText),
              Row(children: [
                if (connected) ...[
                  GestureDetector(
                    onTap: _sendRom,
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17171F),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withOpacity(.14)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.upload_file, size: 14, color: kCyan),
                        SizedBox(width: 6),
                        Text('Send ROM', style: TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _abSwap = !_abSwap),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _abSwap ? const Color(0xFF1D2B22) : const Color(0xFF17171F),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (_abSwap ? kGreen : Colors.white).withValues(alpha: .25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.swap_horiz, size: 14,
                             color: _abSwap ? kGreen : kMuted),
                        const SizedBox(width: 6),
                        Text(_abSwap ? 'A⇄B ON' : 'A⇄B',
                          style: TextStyle(
                            color: _abSwap ? kGreen : kMuted,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  // Back (exit game -> library) and Close (stop game) controls
                  GestureDetector(
                    onTap: () { _conn.control('back'); HapticFeedback.lightImpact(); },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17171F),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withOpacity(.14)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.arrow_back, size: 14, color: kAmber),
                        SizedBox(width: 6),
                        Text('Back', style: TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () { _conn.control('close'); HapticFeedback.lightImpact(); },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241418),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.redAccent.withOpacity(.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.close, size: 14, color: Colors.redAccent),
                        SizedBox(width: 6),
                        Text('Close', style: TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
                _pill(icon: Icons.bolt, color: kCyan, text: '${_conn.latencyMs} ms'),
              ]),
            ]),
          ),
          const Spacer(),
          // Shoulders + Start/Select (momentary: down on touch, up on release)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _shoulder('L', () => _press('l', true), () => _press('l', false)),
              Row(children: [
                _pillBtn('SELECT', () => _press('select', true), () => _press('select', false)),
                const SizedBox(width: 10),
                _pillBtn('START', () => _press('start', true), () => _press('start', false)),
              ]),
              _shoulder('R', () => _press('r', true), () => _press('r', false)),
            ]),
          ),
          const SizedBox(height: 24),
          // D-pad + face
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
              _dPad(),
              _face(),
            ]),
          ),
          const Spacer(),
        ]),
      ),
    );
  }

  Widget _pill({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF17171F),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 9, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _pillBtn(String label, VoidCallback onDown, VoidCallback onUp) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: Container(
        width: 74, height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
          color: Colors.white.withValues(alpha: .07),
        ),
        child: Text(label, style: const TextStyle(color: kMuted, fontSize: 9, letterSpacing: 1.5)),
      ),
    );
  }

  Widget _shoulder(String label, VoidCallback onDown, VoidCallback onUp) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: Container(
        width: 84, height: 30, alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          color: Colors.white.withValues(alpha: .05),
        ),
        child: Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
      ),
    );
  }

  // ---------- D-pad ----------
  Widget _dPad() {
    return SizedBox(
      width: 190, height: 190,
      child: Stack(children: [
        _dpadArm('dpad_up',   66, 0, 58, 62),
        _dpadArm('dpad_down', 66, 190 - 62, 58, 62),
        _dpadArm('dpad_left', 0, 66, 62, 58),
        _dpadArm('dpad_right',190 - 62, 66, 62, 58),
        Center(child: Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(12)))),
      ]),
    );
  }

  Widget _dpadArm(String btn, double l, double t, double wdt, double hgt) {
    return Positioned(
      left: l, top: t, width: wdt, height: hgt,
      child: _GlowButton(
        color: kCyan, held: _held.contains(btn),
        onDown: () => _press(btn, true), onUp: () => _press(btn, false),
        radius: 14, translucent: true,
      ),
    );
  }

  // ---------- Face buttons ----------
  Widget _face() {
    return SizedBox(
      width: 230, height: 210,
      child: Stack(children: [
        _faceBtn('a', 84, 138, kGreen),
        _faceBtn('b', 6, 92, kPurple),
        _faceBtn('y', 84, 46, kPurple),
        _faceBtn('x', 162, 92, kPurple),
      ]),
    );
  }

  Widget _faceBtn(String btn, double l, double t, Color accent) {
    return Positioned(
      left: l.toDouble(), top: t.toDouble(),
      child: _GlowButton(
        color: accent, held: _held.contains(btn),
        onDown: () => _press(btn, true), onUp: () => _press(btn, false),
        circle: true, label: btn.toUpperCase(),
        width: 64, height: 64,   // big reliable tap target (was tiny before)
      ),
    );
  }
}

/// A button with a translucent resting state and a soft outer glow when held/pressed.
class _GlowButton extends StatefulWidget {
  final Color color;
  final bool held;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final bool circle;
  final String? label;
  final double radius;
  final bool translucent;
  final double? width;
  final double? height;
  const _GlowButton({
    required this.color, required this.held, required this.onDown, required this.onUp,
    this.circle = false, this.label, this.radius = 14, this.translucent = false,
    this.width, this.height,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _pressed || widget.held;
    final dim = widget.translucent ? .16 : .30;
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circle ? null : BorderRadius.circular(widget.radius),
          color: widget.color.withValues(alpha: active ? 1.0 : dim),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
          boxShadow: active
              ? [
                  BoxShadow(color: widget.color.withValues(alpha: .6), blurRadius: 26, spreadRadius: 4),
                  BoxShadow(color: widget.color.withValues(alpha: .25), blurRadius: 60, spreadRadius: 12),
                ]
              : const [],
        ),
        child: widget.label == null
            ? null
            : Center(child: Text(widget.label!, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
      ),
    );
  }
}
