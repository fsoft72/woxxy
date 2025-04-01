class User {
  final String username;
  final String? profileImage;
  final String defaultDownloadDirectory;
  final bool enableMd5Checksum;

  User(
      {required this.username,
      this.profileImage,
      required this.defaultDownloadDirectory,
      this.enableMd5Checksum = true});

  // Factory constructor to create a User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'] as String,
      profileImage: json['profileImage'] as String?,
      // Handle potential null if upgrading or if key doesn't exist yet
      defaultDownloadDirectory: json['defaultDownloadDirectory'] as String? ?? '',
      enableMd5Checksum: json['enableMd5Checksum'] as bool? ?? true,
    );
  }

  // Convert User instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'profileImage': profileImage,
      'defaultDownloadDirectory': defaultDownloadDirectory,
      'enableMd5Checksum': enableMd5Checksum,
    };
  }

  // Create a copy of User with optional field updates
  User copyWith({
    String? username,
    String? profileImage,
    String? defaultDownloadDirectory,
    bool? enableMd5Checksum,
  }) {
    return User(
      username: username ?? this.username, // If username is null use current
      profileImage: profileImage ?? this.profileImage, // If profileImage is null use current
      defaultDownloadDirectory: defaultDownloadDirectory ?? this.defaultDownloadDirectory,
      enableMd5Checksum: enableMd5Checksum ?? this.enableMd5Checksum,
    );
  }
}
