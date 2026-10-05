import '../config/network_constants.dart';

/// Who this device is on the network: the one place that holds the local address, name and
/// avatar, read by every service that announces or sends something.
class LocalIdentity {
  /// Creates an identity; an empty [username] becomes [DEFAULT_USERNAME].
  LocalIdentity({this.ipAddress, String username = DEFAULT_USERNAME, this.profileImagePath, this.avatarHash})
      : _username = username.isEmpty ? DEFAULT_USERNAME : username;

  /// Local IPv4 address used to announce this device, null while unknown.
  String? ipAddress;

  /// Path of the profile image file, null when there is none.
  String? profileImagePath;

  /// MD5 of the profile image, announced so peers can refresh their cached copy.
  String? avatarHash;

  String _username;

  /// Display name shown to peers; never empty.
  String get username => _username;
  set username(String value) => _username = value.isEmpty ? DEFAULT_USERNAME : value;
}
