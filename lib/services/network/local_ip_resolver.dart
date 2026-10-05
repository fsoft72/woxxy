import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:woxxy/funcs/debug.dart';

/// A network interface reduced to what the address choice needs.
class LocalInterface {
  final String name;
  final List<String> addresses;

  const LocalInterface(this.name, this.addresses);
}

/// Interface names of virtual adapters (containers, VMs, VPNs) that are not the LAN card.
// ignore: non_constant_identifier_names
final RegExp _VIRTUAL_INTERFACE = RegExp(
  r'^(docker|veth|br-|virbr|vbox|vmnet|vmware|tun|tap|tailscale|zt|wg|vethernet|virtualbox|loopback)|vmware|virtual',
  caseSensitive: false,
);

bool _isUsable(String address) => address != '0.0.0.0' && !address.startsWith('169.254') && !address.startsWith('127.');

bool _isPrivate(String address) {
  if (address.startsWith('10.') || address.startsWith('192.168.')) return true;
  final match = RegExp(r'^172\.(\d+)\.').firstMatch(address);
  final second = match == null ? null : int.parse(match.group(1)!);
  return second != null && second >= 16 && second <= 31;
}

/// Chooses the address to announce: a private address of a real adapter first, then any address
/// of a real adapter, and only as a last resort an address of a virtual adapter. Returns null when
/// there is no usable IPv4 address.
String? pickLocalAddress(List<LocalInterface> interfaces) {
  String? bestOf(bool Function(LocalInterface) interfaceFilter, bool Function(String) addressFilter) {
    for (final interface in interfaces.where(interfaceFilter)) {
      for (final address in interface.addresses) {
        if (_isUsable(address) && addressFilter(address)) return address;
      }
    }
    return null;
  }

  bool real(LocalInterface i) => !_VIRTUAL_INTERFACE.hasMatch(i.name);
  return bestOf(real, _isPrivate) ?? bestOf(real, (_) => true) ?? bestOf((_) => true, _isPrivate) ?? bestOf((_) => true, (_) => true);
}

/// Finds the local IPv4 address used to announce this device.
class LocalIpResolver {
  final Future<String?> Function() _wifiIp;
  final Future<List<LocalInterface>> Function() _interfaces;

  /// [wifiIp] and [interfaces] are injectable for tests; by default they query the system.
  LocalIpResolver({Future<String?> Function()? wifiIp, Future<List<LocalInterface>> Function()? interfaces})
      : _wifiIp = wifiIp ?? (() => NetworkInfo().getWifiIP()),
        _interfaces = interfaces ?? _systemInterfaces;

  static Future<List<LocalInterface>> _systemInterfaces() async {
    final list = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false, type: InternetAddressType.IPv4);
    return [for (final i in list) LocalInterface(i.name, [for (final a in i.addresses) a.address])];
  }

  /// The Wi-Fi address when the platform reports one, otherwise the best interface address.
  /// A failing Wi-Fi lookup never prevents the interface search.
  Future<String?> call() async {
    try {
      final wifi = await _wifiIp();
      if (wifi != null && wifi.isNotEmpty && wifi != '0.0.0.0') {
        zprint('✅ Found WiFi IP: $wifi');
        return wifi;
      }
      zprint('⚠️ WiFi IP not found or invalid ($wifi). Checking other interfaces...');
    } catch (e) {
      zprint('⚠️ WiFi IP lookup failed: $e. Checking other interfaces...');
    }

    try {
      final address = pickLocalAddress(await _interfaces());
      zprint(address == null ? '❌ Could not determine a suitable IP address.' : '✅ Using interface address: $address');
      return address;
    } catch (e) {
      zprint('❌ Error listing network interfaces: $e');
      return null;
    }
  }
}
