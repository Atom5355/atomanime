/// User profile model for Supabase
class Profile {
  final String id;
  final String name;
  final String pinHash; // Hashed 5-digit PIN
  final String? avatarColor; // Hex color for avatar
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  Profile({
    required this.id,
    required this.name,
    required this.pinHash,
    this.avatarColor,
    required this.createdAt,
    this.lastLoginAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      pinHash: json['pin_hash'] as String,
      avatarColor: json['avatar_color'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null 
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pin_hash': pinHash,
      'avatar_color': avatarColor,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  Profile copyWith({
    String? id,
    String? name,
    String? pinHash,
    String? avatarColor,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      pinHash: pinHash ?? this.pinHash,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

/// Device-profile link with remember PIN option
class DeviceProfile {
  final String id;
  final String deviceId;
  final String profileId;
  final bool rememberPin; // If true, auto-login; if false, require PIN each time
  final DateTime linkedAt;

  DeviceProfile({
    required this.id,
    required this.deviceId,
    required this.profileId,
    required this.rememberPin,
    required this.linkedAt,
  });

  factory DeviceProfile.fromJson(Map<String, dynamic> json) {
    return DeviceProfile(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      profileId: json['profile_id'] as String,
      rememberPin: json['remember_pin'] as bool? ?? false,
      linkedAt: DateTime.parse(json['linked_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'profile_id': profileId,
      'remember_pin': rememberPin,
      'linked_at': linkedAt.toIso8601String(),
    };
  }
}

/// Watch history entry for tracking anime progress
class WatchHistory {
  final String id;
  final String profileId;
  final String animeId;
  final String animeTitle;
  final String? coverImage;
  final int episodeNumber;
  final String episodeId;
  final String category; // 'sub' or 'dub'
  final Duration watchedDuration; // How far into the episode
  final Duration totalDuration; // Total episode duration
  final bool completed; // Marked as watched
  final DateTime updatedAt;

  WatchHistory({
    required this.id,
    required this.profileId,
    required this.animeId,
    required this.animeTitle,
    this.coverImage,
    required this.episodeNumber,
    required this.episodeId,
    required this.category,
    required this.watchedDuration,
    required this.totalDuration,
    required this.completed,
    required this.updatedAt,
  });

  /// Progress as a percentage (0.0 - 1.0)
  double get progress {
    if (totalDuration.inSeconds == 0) return 0;
    return watchedDuration.inSeconds / totalDuration.inSeconds;
  }

  /// Check if episode should show resume option (watched at least 30 seconds, not completed)
  bool get canResume => !completed && watchedDuration.inSeconds >= 30;

  factory WatchHistory.fromJson(Map<String, dynamic> json) {
    return WatchHistory(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      animeId: json['anime_id'] as String,
      animeTitle: json['anime_title'] as String,
      coverImage: json['cover_image'] as String?,
      episodeNumber: json['episode_number'] as int,
      episodeId: json['episode_id'] as String,
      category: json['category'] as String,
      watchedDuration: Duration(seconds: json['watched_seconds'] as int? ?? 0),
      totalDuration: Duration(seconds: json['total_seconds'] as int? ?? 0),
      completed: json['completed'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'anime_id': animeId,
      'anime_title': animeTitle,
      'cover_image': coverImage,
      'episode_number': episodeNumber,
      'episode_id': episodeId,
      'category': category,
      'watched_seconds': watchedDuration.inSeconds,
      'total_seconds': totalDuration.inSeconds,
      'completed': completed,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WatchHistory copyWith({
    String? id,
    String? profileId,
    String? animeId,
    String? animeTitle,
    String? coverImage,
    int? episodeNumber,
    String? episodeId,
    String? category,
    Duration? watchedDuration,
    Duration? totalDuration,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return WatchHistory(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      coverImage: coverImage ?? this.coverImage,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeId: episodeId ?? this.episodeId,
      category: category ?? this.category,
      watchedDuration: watchedDuration ?? this.watchedDuration,
      totalDuration: totalDuration ?? this.totalDuration,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
