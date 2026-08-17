import 'dart:math' as math;
import 'package:flutter/gestures.dart';
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
  ConnState _prevState = ConnState.disconnected;
  int _lastLatencyShown = 0;

  @override
  void initState() {
    super.initState();
    _conn = Connection(host: widget.host, port: widget.port, player: widget.player)
      ..deviceLabel = 'FlutterController-${widget.player}'
      ..addListener(_onConnChanged)
      ..onResync = () {
          // TV's emulator relay restarted and cleared core state: re-press whatever
          // we're still holding so no button is lost (fixes auto-walk after a blip).
          if (mounted && _conn.state == ConnState.connected) {
            for (final b in _held.toList()) {
              _conn.input(b, 'down');
            }
          }
        };
    _conn.connect();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Connection state changed: only act on REAL transitions (connect/disconnect).
  /// On reconnect, RE-SEND held buttons as down (the TV cleared everything when we
  /// dropped) — a mid-hold Wi-Fi blip therefore never feels like a stuck control.
  void _onConnChanged() {
    if (!mounted) return;
    final st = _conn.state;
    final changed = st != _prevState;
    if (changed) {
      if (st == ConnState.connected) {
        for (final b in _held.toList()) {
          _conn.input(b, 'down'); // re-press whatever the user still holds
        }
      } else if (st == ConnState.reconnecting || st == ConnState.disconnected) {
        _held.clear(); // link dropped; TV auto-released — start clean
      }
      _prevState = st;
    }
    // Only rebuild when something visible changed (state/latency), never per pong.
    if (changed || _conn.latencyMs != _lastLatencyShown) {
      _lastLatencyShown = _conn.latencyMs;
      setState(() {});
    }
  }

  /// Send 'up' for every held button and clear the set (phone/TV resync).
  void _releaseAll() {
    if (_held.isEmpty) return;
    for (final b in _held.toList()) {
      _conn.input(b, 'up'); // best-effort release
    }
    setState(_held.clear);
  }

  @override
  void dispose() {
    _conn.removeListener(_onConnChanged);
    _conn.dispose();
    super.dispose();
  }

  void _press(String button, bool down, {bool haptic = true}) {
    if (haptic) HapticFeedback.lightImpact(); // haptic on every press
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
  /// third-party picker plugin is needed. Streams in 256KB chunks (no OOM on ISOs).
  Future<void> _sendRom() async {
    if (_conn.state != ConnState.connected) return;
    const channel = MethodChannel('retrolan/filepicker');
    try {
      final Map<dynamic, dynamic>? picked =
          await channel.invokeMethod('pickFile') as Map<dynamic, dynamic>?;
      if (picked == null || picked.isEmpty) return; // user cancelled
      final name = picked['name'] as String;
      final size = (picked['size'] as num?)?.toInt() ?? 0;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Sending $name to TV…'),
          duration: const Duration(seconds: 30),
        ),
      );
      var lastPct = -1;
      final ok = await _conn.sendRomStream(
        Map<String, dynamic>.from(picked),
        onProgress: (sent, total) {
          if (total > 0) {
            final pct = (sent * 100 / total).floor();
            if (pct != lastPct && pct % 10 == 0) {
              lastPct = pct;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Sending $name… $pct% ($size bytes)'),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        },
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '✓ $name sent — playing on TV' : 'Not connected to TV')),
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
          // 8 game buttons: L2 L R2 | SELECT START | R (momentary: down/up)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                _shoulder('L2', () => _press('l2', true), () => _press('l2', false)),
                const SizedBox(width: 8),
                _shoulder('L', () => _press('l', true), () => _press('l', false)),
              ]),
              Row(children: [
                _pillBtn('SELECT', () => _press('select', true), () => _press('select', false)),
                const SizedBox(width: 10),
                _pillBtn('START', () => _press('start', true), () => _press('start', false)),
              ]),
              Row(children: [
                _shoulder('R', () => _press('r', true), () => _press('r', false)),
                const SizedBox(width: 8),
                _shoulder('R2', () => _press('r2', true), () => _press('r2', false)),
              ]),
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
    final pointers = <int>{};
    return Listener(
      onPointerDown: (e) { pointers.add(e.pointer); onDown(); },
      onPointerUp: (e) { pointers.remove(e.pointer); if (pointers.isEmpty) onUp(); },
      onPointerCancel: (e) { pointers.remove(e.pointer); if (pointers.isEmpty) onUp(); },
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
    final pointers = <int>{};
    return Listener(
      onPointerDown: (e) { pointers.add(e.pointer); onDown(); },
      onPointerUp: (e) { pointers.remove(e.pointer); if (pointers.isEmpty) onUp(); },
      onPointerCancel: (e) { pointers.remove(e.pointer); if (pointers.isEmpty) onUp(); },
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
  // ---------- Round 360° pad ----------
  // Touch anywhere on the circle; the position maps to 8-way direction (diagonals
  // included, like a real analog stick). Center = neutral, edges = full direction.
  final Set<String> _padActive = {};

  Widget _dPad() {
    const size = 190.0;
    const c = size / 2;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _padMove(e),
      onPointerMove: (e) => _padMove(e),
      onPointerUp: (_) => _padClear(),
      onPointerCancel: (_) => _padClear(),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF121218),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 18, offset: const Offset(0, 6)),
            BoxShadow(color: kCyan.withValues(alpha: _padActive.isEmpty ? .05 : .22), blurRadius: 30),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          // direction guides (visual only) — light up when that direction is active
          _padGuide('dpad_up',    c - 29, 0,      58, 62),
          _padGuide('dpad_down',  c - 29, size - 62, 58, 62),
          _padGuide('dpad_left',  0,      c - 29, 62, 58),
          _padGuide('dpad_right', size - 62, c - 29, 62, 58),
          // diagonal guide dots (NW NE SW SE)
          _padDot('dpad_up_left',    c - 66, c - 66),
          _padDot('dpad_up_right',   c + 20, c - 66),
          _padDot('dpad_down_left',  c - 66, c + 20),
          _padDot('dpad_down_right', c + 20, c + 20),
          // center nub (neutral)
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .06),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _padGuide(String btn, double l, double t, double wdt, double hgt) {
    final on = _held.contains(btn);
    return Positioned(
      left: l, top: t, width: wdt, height: hgt,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: kCyan.withValues(alpha: on ? .55 : .08),
            border: Border.all(color: kCyan.withValues(alpha: on ? .9 : .12)),
          ),
        ),
      ),
    );
  }

  Widget _padDot(String btn, double l, double t) {
    final on = _held.contains(btn);
    return Positioned(
      left: l, top: t,
      child: IgnorePointer(
        child: Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? kCyan.withValues(alpha: .9) : Colors.white.withValues(alpha: .08),
          ),
        ),
      ),
    );
  }

  /// Map a pointer position inside the pad to an 8-way direction set.
  void _padMove(PointerEvent e) {
    const size = 190.0;
    const c = size / 2;
    final dx = e.localPosition.dx - c;
    final dy = e.localPosition.dy - c;
    final dist = math.sqrt(dx * dx + dy * dy);
    Set<String> target = {};
    if (dist > 26) { // center dead zone = neutral
      var deg = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
      if (deg < 22.5 || deg >= 337.5) {
        target = {'dpad_right'};
      } else if (deg < 67.5) {
        target = {'dpad_down', 'dpad_right'};
      } else if (deg < 112.5) {
        target = {'dpad_down'};
      } else if (deg < 157.5) {
        target = {'dpad_down', 'dpad_left'};
      } else if (deg < 202.5) {
        target = {'dpad_left'};
      } else if (deg < 247.5) {
        target = {'dpad_up', 'dpad_left'};
      } else if (deg < 292.5) {
        target = {'dpad_up'};
      } else {
        target = {'dpad_up', 'dpad_right'};
      }
    }
    // Diff against what's active: press new, release removed.
    for (final b in _padActive.difference(target)) { _press(b, false, haptic: false); }
    for (final b in target.difference(_padActive)) { _press(b, true, haptic: false); }
    _padActive
      ..clear()
      ..addAll(target);
  }

  void _padClear() {
    for (final b in _padActive) { _press(b, false, haptic: false); }
    _padActive.clear();
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
  // Track pointers per button: a pointer down on THIS button keeps it held until that
  // pointer lifts — no gesture-arena "slop" cancellation, true multi-touch.
  final Set<int> _pointers = {};

  void _down(int pointer) {
    _pointers.add(pointer);
    if (!_pressed) { setState(() => _pressed = true); widget.onDown(); }
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty && _pressed) {
      setState(() => _pressed = false);
      widget.onUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _pressed || widget.held;
    final dim = widget.translucent ? .16 : .30;
    return Listener(
      onPointerDown: (e) => _down(e.pointer),
      onPointerUp: (e) => _up(e.pointer),
      onPointerCancel: (e) => _up(e.pointer),
      // Pointer moving away does NOT release (a real gamepad doesn't either) — the
      // button stays held until the finger lifts. Prevents the "stuck/loose" feel.
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
