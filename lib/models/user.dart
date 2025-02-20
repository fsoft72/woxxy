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
      defaultDownloadDirectory: json['defaultDownloadDirectory'] as String,
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

  // Create a copy of User with optional field updates
  User copyWith({
    String? username,
    String? profileImage,
    String? defaultDownloadDirectory,
  }) {
    return User(
      username: username ?? this.username,
      profileImage: profileImage ?? this.profileImage,
      defaultDownloadDirectory: defaultDownloadDirectory ?? this.defaultDownloadDirectory,
    );
  }
}
