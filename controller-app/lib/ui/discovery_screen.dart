import 'package:flutter/material.dart';
import '../discovery/discovery.dart';
import '../discovery/tv_peer.dart';
import '../main.dart' show kBg, kPurple, kMuted, kInk;
import 'gamepad_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _disc = Discovery();
  final _ipCtrl = TextEditingController();
  int _player = 1;

  @override
  void initState() {
    super.initState();
    _disc.addListener(() => setState(() {}));
    _disc.start();
  }

  @override
  void dispose() {
    _disc.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  void _connect(TvPeer peer) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GamepadScreen(host: peer.host, port: peer.port, player: _player),
    ));
  }

  void _manual() {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    final peer = TvPeer(name: ip, host: ip);
    _disc.addManual(ip);
    _connect(peer);
  }

  @override
  Widget build(BuildContext context) {
    final peers = [..._disc.peers, ..._disc.manualPeers];
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 32, 28, 8),
              child: Text('RetroLAN', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -1)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Text('Find your console on this Wi-Fi network.', style: TextStyle(color: kMuted, fontSize: 15)),
            ),
            // Player selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(children: [
                const Text('Playing as', style: TextStyle(color: kMuted)),
                const SizedBox(width: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Player 1')),
                    ButtonSegment(value: 2, label: Text('Player 2')),
                  ],
                  selected: {_player},
                  onSelectionChanged: (s) => setState(() => _player = s.first),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: peers.isEmpty
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: kPurple),
                      SizedBox(height: 16),
                      Text('Searching for TVs…', style: TextStyle(color: kMuted)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: peers.length,
                      itemBuilder: (_, i) {
                        final p = peers[i];
                        return Card(
                          color: const Color(0xFF17171F),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: const Icon(Icons.tv, color: kPurple),
                            title: Text(p.name, style: const TextStyle(color: kInk, fontWeight: FontWeight.w600)),
                            subtitle: Text('${p.host}:${p.port}', style: const TextStyle(color: kMuted, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: kMuted),
                            onTap: () => _connect(p),
                          ),
                        );
                      },
                    ),
            ),
            // Manual entry
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: kInk),
                    decoration: InputDecoration(
                      hintText: 'Enter TV IP (e.g. 192.168.1.50)',
                      hintStyle: const TextStyle(color: kMuted),
                      filled: true, fillColor: const Color(0xFF17171F),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _manual(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(onPressed: _manual, child: const Text('Connect')),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
