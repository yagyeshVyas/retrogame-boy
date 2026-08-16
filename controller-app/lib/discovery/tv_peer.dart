/// A discovered TV host on the LAN.
class TvPeer {
  final String name;
  final String host;
  final int port;
  const TvPeer({required this.name, required this.host, this.port = 8877});
  @override String toString() => name;
}
