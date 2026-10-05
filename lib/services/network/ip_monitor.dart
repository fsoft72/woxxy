// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:woxxy/funcs/debug.dart';

/// Default time between two checks of the local IP address.
const Duration DEFAULT_IP_CHECK_INTERVAL = Duration(seconds: 15);

/// Periodically resolves the local IP and reports when it changes (Wi-Fi switch, VPN, cable plugged).
class IpMonitor {
  final Future<String?> Function() resolver;
  final void Function(String? oldIp, String? newIp) onChanged;
  final Duration interval;

  Timer? _timer;
  String? _currentIp;
  bool _checking = false;

  IpMonitor({required this.resolver, required this.onChanged, this.interval = DEFAULT_IP_CHECK_INTERVAL});

  /// Starts watching, treating [initialIp] as the current address.
  void start(String? initialIp) {
    _currentIp = initialIp;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
  }

  /// Stops watching.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Resolves the IP once and notifies if it differs from the last known one.
  /// Overlapping checks are skipped.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final ip = await resolver();
      if (ip == _currentIp) return;
      final old = _currentIp;
      _currentIp = ip;
      zprint('🌐 Local IP changed: $old -> $ip');
      onChanged(old, ip);
    } catch (e) {
      zprint('⚠️ IP check failed: $e');
    } finally {
      _checking = false;
    }
  }
}
