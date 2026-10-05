class User {
  final String username;
  final String? profileImage;
  final String defaultDownloadDirectory;

  User({
    required this.username,
    this.profileImage,
    required this.defaultDownloadDirectory,
  });

  // Factory constructor to create a User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'] as String,
      profileImage: json['profileImage'] as String?,
      // Handle potential null if upgrading or if key doesn't exist yet
      defaultDownloadDirectory: json['defaultDownloadDirectory'] as String? ?? '',
    );
  }

  // Convert User instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'profileImage': profileImage,
      'defaultDownloadDirectory': defaultDownloadDirectory,
    };
  }

  /// Copy of this user with some fields replaced. A null argument keeps the current value;
  /// [clearProfileImage] removes the profile picture instead.
  User copyWith({
    String? username,
    String? profileImage,
    bool clearProfileImage = false,
    String? defaultDownloadDirectory,
  }) {
    return User(
      username: username ?? this.username,
      profileImage: clearProfileImage ? null : (profileImage ?? this.profileImage),
      defaultDownloadDirectory: defaultDownloadDirectory ?? this.defaultDownloadDirectory,
    );
  }
}
