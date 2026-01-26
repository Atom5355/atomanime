import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';

/// Supabase configuration
class SupabaseConfig {
  // Supabase project configuration
  static const String supabaseUrl = 'https://pbayelyqvqzxglzlomdy.supabase.co';
  static const String supabaseAnonKey = 'sb_secret_RrOIlbDlhIsJzkhNzor0kw_YjtD4iR7';
}

/// Service for managing profiles and watch history via Supabase
class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final _uuid = const Uuid();
  
  SupabaseClient? _supabase;
  Profile? _currentProfile;
  String? _deviceId;
  List<Profile> _deviceProfiles = [];
  bool _isInitialized = false;

  Profile? get currentProfile => _currentProfile;
  List<Profile> get deviceProfiles => _deviceProfiles;
  bool get isLoggedIn => _currentProfile != null;
  bool get isInitialized => _isInitialized;
  String? get deviceId => _deviceId;

  /// Initialize Supabase and load device info
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      );
      _supabase = Supabase.instance.client;
      
      // Get or create device ID
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('device_id');
      if (_deviceId == null) {
        _deviceId = _uuid.v4();
        await prefs.setString('device_id', _deviceId!);
      }
      
      // Load profiles linked to this device
      await _loadDeviceProfiles();
      
      // Check for auto-login profile
      await _checkAutoLogin();
      
      _isInitialized = true;
      notifyListeners();
      debugPrint('ProfileService initialized. Device ID: $_deviceId');
    } catch (e) {
      debugPrint('ProfileService initialization error: $e');
      // Continue without Supabase for offline mode
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Hash a PIN for storage
  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// Verify a PIN against stored hash
  bool _verifyPin(String pin, String hash) {
    return _hashPin(pin) == hash;
  }

  /// Load profiles linked to this device
  Future<void> _loadDeviceProfiles() async {
    if (_supabase == null || _deviceId == null) return;

    try {
      // Get device-profile links
      final links = await _supabase!
          .from('device_profiles')
          .select('profile_id')
          .eq('device_id', _deviceId!);

      if (links.isEmpty) {
        _deviceProfiles = [];
        return;
      }

      final profileIds = (links as List).map((l) => l['profile_id'] as String).toList();
      
      // Get profiles
      final profiles = await _supabase!
          .from('profiles')
          .select()
          .inFilter('id', profileIds);

      _deviceProfiles = (profiles as List).map((p) => Profile.fromJson(p)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading device profiles: $e');
    }
  }

  /// Check for auto-login (remembered PIN)
  Future<void> _checkAutoLogin() async {
    if (_supabase == null || _deviceId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastProfileId = prefs.getString('last_profile_id');
      
      if (lastProfileId != null) {
        // Check if this profile has remember_pin enabled for this device
        final link = await _supabase!
            .from('device_profiles')
            .select()
            .eq('device_id', _deviceId!)
            .eq('profile_id', lastProfileId)
            .maybeSingle();

        if (link != null && link['remember_pin'] == true) {
          // Auto-login
          final profile = _deviceProfiles.firstWhere(
            (p) => p.id == lastProfileId,
            orElse: () => throw Exception('Profile not found'),
          );
          _currentProfile = profile;
          await _updateLastLogin(profile.id);
        }
      }
    } catch (e) {
      debugPrint('Auto-login check failed: $e');
    }
  }

  /// Check if a profile name already exists
  Future<bool> profileNameExists(String name) async {
    if (_supabase == null) return false;

    try {
      final result = await _supabase!
          .from('profiles')
          .select('id')
          .eq('name', name)
          .maybeSingle();
      
      return result != null;
    } catch (e) {
      debugPrint('Error checking profile name: $e');
      return false;
    }
  }

  /// Create a new profile
  Future<Profile?> createProfile({
    required String name,
    required String pin,
    String? avatarColor,
  }) async {
    if (_supabase == null) return null;

    try {
      // Check if name already exists
      if (await profileNameExists(name)) {
        throw Exception('A profile with this name already exists');
      }
      
      final id = _uuid.v4();
      final now = DateTime.now();
      
      final profileData = {
        'id': id,
        'name': name,
        'pin_hash': _hashPin(pin),
        'avatar_color': avatarColor ?? _generateRandomColor(),
        'created_at': now.toIso8601String(),
        'last_login_at': now.toIso8601String(),
      };

      await _supabase!.from('profiles').insert(profileData);

      final profile = Profile.fromJson(profileData);
      
      // Link to device
      await linkProfileToDevice(profile.id, rememberPin: true);
      
      _deviceProfiles.add(profile);
      notifyListeners();
      
      return profile;
    } catch (e) {
      debugPrint('Error creating profile: $e');
      rethrow; // Rethrow to show error in UI
    }
  }

  /// Link a profile to this device
  Future<bool> linkProfileToDevice(String profileId, {bool rememberPin = false}) async {
    if (_supabase == null || _deviceId == null) return false;

    try {
      // Check if link already exists
      final existing = await _supabase!
          .from('device_profiles')
          .select()
          .eq('device_id', _deviceId!)
          .eq('profile_id', profileId)
          .maybeSingle();

      if (existing != null) {
        // Update remember_pin setting
        await _supabase!
            .from('device_profiles')
            .update({'remember_pin': rememberPin})
            .eq('id', existing['id']);
      } else {
        // Create new link
        await _supabase!.from('device_profiles').insert({
          'id': _uuid.v4(),
          'device_id': _deviceId,
          'profile_id': profileId,
          'remember_pin': rememberPin,
          'linked_at': DateTime.now().toIso8601String(),
        });
      }

      return true;
    } catch (e) {
      debugPrint('Error linking profile to device: $e');
      return false;
    }
  }

  /// Login with profile name and PIN
  Future<Profile?> login({
    required String name,
    required String pin,
    bool rememberPin = false,
  }) async {
    if (_supabase == null) return null;

    try {
      // Find profile by name
      final result = await _supabase!
          .from('profiles')
          .select()
          .eq('name', name)
          .maybeSingle();

      if (result == null) {
        throw Exception('Profile not found');
      }

      final profile = Profile.fromJson(result);
      
      // Verify PIN
      if (!_verifyPin(pin, profile.pinHash)) {
        throw Exception('Invalid PIN');
      }

      // Link to device if not already
      await linkProfileToDevice(profile.id, rememberPin: rememberPin);
      
      // Set as current profile
      _currentProfile = profile;
      await _updateLastLogin(profile.id);
      
      // Save last profile ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_profile_id', profile.id);
      
      // Reload device profiles
      await _loadDeviceProfiles();
      
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }

  /// Login with profile ID and PIN (for device profile selection)
  Future<Profile?> loginWithId({
    required String profileId,
    required String pin,
  }) async {
    if (_supabase == null) return null;

    try {
      final profile = _deviceProfiles.firstWhere(
        (p) => p.id == profileId,
        orElse: () => throw Exception('Profile not found'),
      );

      // Verify PIN
      if (!_verifyPin(pin, profile.pinHash)) {
        throw Exception('Invalid PIN');
      }

      _currentProfile = profile;
      await _updateLastLogin(profile.id);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_profile_id', profile.id);
      
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('Login with ID error: $e');
      rethrow;
    }
  }

  /// Select a profile that has remember_pin enabled (no PIN required)
  Future<bool> selectRememberedProfile(String profileId) async {
    if (_supabase == null || _deviceId == null) return false;

    try {
      // Check if remember_pin is enabled
      final link = await _supabase!
          .from('device_profiles')
          .select()
          .eq('device_id', _deviceId!)
          .eq('profile_id', profileId)
          .maybeSingle();

      if (link == null || link['remember_pin'] != true) {
        return false;
      }

      final profile = _deviceProfiles.firstWhere(
        (p) => p.id == profileId,
        orElse: () => throw Exception('Profile not found'),
      );

      _currentProfile = profile;
      await _updateLastLogin(profile.id);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_profile_id', profile.id);
      
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Select remembered profile error: $e');
      return false;
    }
  }

  /// Check if a profile requires PIN on this device
  Future<bool> requiresPin(String profileId) async {
    if (_supabase == null || _deviceId == null) return true;

    try {
      final link = await _supabase!
          .from('device_profiles')
          .select()
          .eq('device_id', _deviceId!)
          .eq('profile_id', profileId)
          .maybeSingle();

      return link == null || link['remember_pin'] != true;
    } catch (e) {
      return true;
    }
  }

  /// Update remember_pin setting for a profile on this device
  Future<bool> updateRememberPin(String profileId, bool rememberPin) async {
    if (_supabase == null || _deviceId == null) return false;

    try {
      await _supabase!
          .from('device_profiles')
          .update({'remember_pin': rememberPin})
          .eq('device_id', _deviceId!)
          .eq('profile_id', profileId);
      return true;
    } catch (e) {
      debugPrint('Error updating remember_pin: $e');
      return false;
    }
  }

  /// Update last login timestamp
  Future<void> _updateLastLogin(String profileId) async {
    if (_supabase == null) return;

    try {
      await _supabase!
          .from('profiles')
          .update({'last_login_at': DateTime.now().toIso8601String()})
          .eq('id', profileId);
    } catch (e) {
      debugPrint('Error updating last login: $e');
    }
  }

  /// Logout current profile
  Future<void> logout() async {
    _currentProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_profile_id');
    notifyListeners();
  }

  /// Remove profile from device (unlink, don't delete profile)
  Future<bool> removeProfileFromDevice(String profileId) async {
    if (_supabase == null || _deviceId == null) return false;

    try {
      await _supabase!
          .from('device_profiles')
          .delete()
          .eq('device_id', _deviceId!)
          .eq('profile_id', profileId);

      _deviceProfiles.removeWhere((p) => p.id == profileId);
      
      if (_currentProfile?.id == profileId) {
        _currentProfile = null;
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error removing profile from device: $e');
      return false;
    }
  }

  // ============ Watch History Methods ============

  /// Save or update watch progress
  Future<void> updateWatchProgress({
    required String animeId,
    required String animeTitle,
    String? coverImage,
    required int episodeNumber,
    required String episodeId,
    required String category,
    required Duration watchedDuration,
    required Duration totalDuration,
    bool? completed,
  }) async {
    if (_supabase == null || _currentProfile == null) return;

    try {
      // Check if entry exists
      final existing = await _supabase!
          .from('watch_history')
          .select()
          .eq('profile_id', _currentProfile!.id)
          .eq('anime_id', animeId)
          .eq('episode_number', episodeNumber)
          .eq('category', category)
          .maybeSingle();

      final isCompleted = completed ?? 
          (watchedDuration.inSeconds / totalDuration.inSeconds > 0.9);

      final data = {
        'profile_id': _currentProfile!.id,
        'anime_id': animeId,
        'anime_title': animeTitle,
        'cover_image': coverImage,
        'episode_number': episodeNumber,
        'episode_id': episodeId,
        'category': category,
        'watched_seconds': watchedDuration.inSeconds,
        'total_seconds': totalDuration.inSeconds,
        'completed': isCompleted,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null) {
        await _supabase!
            .from('watch_history')
            .update(data)
            .eq('id', existing['id']);
      } else {
        data['id'] = _uuid.v4();
        await _supabase!.from('watch_history').insert(data);
      }
    } catch (e) {
      debugPrint('Error updating watch progress: $e');
    }
  }

  /// Get resume position for an episode
  Future<Duration?> getResumePosition({
    required String animeId,
    required int episodeNumber,
    required String category,
  }) async {
    if (_supabase == null || _currentProfile == null) return null;

    try {
      final result = await _supabase!
          .from('watch_history')
          .select()
          .eq('profile_id', _currentProfile!.id)
          .eq('anime_id', animeId)
          .eq('episode_number', episodeNumber)
          .eq('category', category)
          .maybeSingle();

      if (result == null) return null;
      
      final history = WatchHistory.fromJson(result);
      
      // Only return resume position if not completed and watched at least 30 seconds
      if (history.canResume) {
        return history.watchedDuration;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting resume position: $e');
      return null;
    }
  }

  /// Get watch history for current profile
  Future<List<WatchHistory>> getWatchHistory({int limit = 50}) async {
    if (_supabase == null || _currentProfile == null) return [];

    try {
      final results = await _supabase!
          .from('watch_history')
          .select()
          .eq('profile_id', _currentProfile!.id)
          .order('updated_at', ascending: false)
          .limit(limit);

      return (results as List).map((r) => WatchHistory.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Error getting watch history: $e');
      return [];
    }
  }

  /// Get continue watching list (unfinished episodes)
  Future<List<WatchHistory>> getContinueWatching({int limit = 20}) async {
    if (_supabase == null || _currentProfile == null) return [];

    try {
      final results = await _supabase!
          .from('watch_history')
          .select()
          .eq('profile_id', _currentProfile!.id)
          .eq('completed', false)
          .gte('watched_seconds', 30) // At least 30 seconds watched
          .order('updated_at', ascending: false)
          .limit(limit);

      return (results as List).map((r) => WatchHistory.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Error getting continue watching: $e');
      return [];
    }
  }

  /// Get watch progress for all episodes of an anime
  Future<Map<int, WatchHistory>> getAnimeProgress(String animeId, String category) async {
    if (_supabase == null || _currentProfile == null) return {};

    try {
      final results = await _supabase!
          .from('watch_history')
          .select()
          .eq('profile_id', _currentProfile!.id)
          .eq('anime_id', animeId)
          .eq('category', category);

      final map = <int, WatchHistory>{};
      for (final r in results) {
        final history = WatchHistory.fromJson(r);
        map[history.episodeNumber] = history;
      }
      return map;
    } catch (e) {
      debugPrint('Error getting anime progress: $e');
      return {};
    }
  }

  /// Mark episode as completed
  Future<void> markAsCompleted({
    required String animeId,
    required int episodeNumber,
    required String category,
  }) async {
    if (_supabase == null || _currentProfile == null) return;

    try {
      await _supabase!
          .from('watch_history')
          .update({
            'completed': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('profile_id', _currentProfile!.id)
          .eq('anime_id', animeId)
          .eq('episode_number', episodeNumber)
          .eq('category', category);
    } catch (e) {
      debugPrint('Error marking as completed: $e');
    }
  }

  /// Clear watch history for an anime
  Future<void> clearAnimeHistory(String animeId) async {
    if (_supabase == null || _currentProfile == null) return;

    try {
      await _supabase!
          .from('watch_history')
          .delete()
          .eq('profile_id', _currentProfile!.id)
          .eq('anime_id', animeId);
    } catch (e) {
      debugPrint('Error clearing anime history: $e');
    }
  }

  /// Generate a random avatar color
  String _generateRandomColor() {
    final colors = [
      '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3',
      '#03A9F4', '#00BCD4', '#009688', '#4CAF50', '#8BC34A',
      '#CDDC39', '#FFEB3B', '#FFC107', '#FF9800', '#FF5722',
    ];
    return colors[DateTime.now().millisecond % colors.length];
  }
}
