/// mDNS / DNS-SD discovery of the RetroLAN TV service (`_retrolan._tcp`).
/// Falls back to manual IP entry for networks that block multicast.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'tv_peer.dart';

/// Mutable list of discovered peers. This is a ChangeNotifier so the UI
/// rebuilds whenever a TV is found.
class Discovery extends ChangeNotifier {
  final List<TvPeer> peers = [];
  final List<TvPeer> manualPeers = [];

  MDnsClient? _client;
  final List<StreamSubscription> _subs = [];

  static const String _serviceType = '_retrolan._tcp.local';

  /// Begin browsing for _retrolan._tcp services.
  Future<void> start() async {
    peers.clear();
    _cancelSubs();
    notifyListeners();

    try {
      _client = MDnsClient();
      await _client!.start();

      // 1) PTR query -> discover service instance names
      final ptrSub = _client!
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceType),
          )
          .listen((ptr) {
        _resolveService(ptr.domainName);
      });
      _subs.add(ptrSub);
    } catch (e) {
      debugPrint('mDNS unavailable: $e (use manual IP entry)');
    }
  }

  Future<void> _resolveService(String domain) async {
    try {
      // 2) SRV query -> host target + port
      final srv = await _client!
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(domain))
          .first;
      // 3) A query -> IPv4 address
      final a = await _client!
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )
          .first;
      final name = domain.split('.')[0];
      final peer = TvPeer(name: name, host: a.address.address, port: srv.port);
      if (!peers.any((p) => p.host == peer.host && p.port == peer.port)) {
        peers.add(peer);
        notifyListeners();
      }
    } catch (_) {
      // best-effort: some instances won't resolve; skip them.
    }
  }

  void addManual(String ip, {int port = 8877}) {
    final peer = TvPeer(name: ip, host: ip, port: port);
    if (!manualPeers.any((p) => p.host == peer.host)) manualPeers.add(peer);
    notifyListeners();
  }

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _cancelSubs();
    _client?.stop();
    super.dispose();
  }
}
