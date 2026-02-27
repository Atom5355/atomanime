import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'aniwatch_service.dart';
import 'bundled_tools.dart';
import 'profile_service.dart';

/// Manages episode downloads and caching for offline viewing (per-profile)
class DownloadCacheService {
  static final DownloadCacheService _instance = DownloadCacheService._internal();
  factory DownloadCacheService() => _instance;
  DownloadCacheService._internal();

  final AniwatchService _aniwatchService = AniwatchService();
  final ProfileService _profileService = ProfileService();
  
  // Download state tracking
  final Map<String, DownloadTask> _activeDownloads = {};
  final List<Function(DownloadTask)> _progressListeners = [];
  
  /// Get the current profile ID (or 'default' if not logged in)
  String get _currentProfileId {
    return _profileService.currentProfile?.id ?? 'default';
  }
  
  /// Get the base directory for downloads (platform-aware)
  Future<String> get _baseDownloadsPath async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Use app documents directory on mobile
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    } else {
      // Desktop: use current directory for dev, exe directory for production
      return BundledTools.isDevelopment 
          ? Directory.current.path 
          : BundledTools.exeDir;
    }
  }
  
  /// Get the base downloads directory for the current profile
  Future<Directory> get downloadsDir async {
    final baseDir = await _baseDownloadsPath;
    final profileId = _currentProfileId;
    final dir = Directory(path.join(baseDir, 'downloads', profileId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  
  /// Get downloads directory for a specific profile
  Future<Directory> getDownloadsDirForProfile(String profileId) async {
    final baseDir = await _baseDownloadsPath;
    final dir = Directory(path.join(baseDir, 'downloads', profileId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  
  /// Get the directory for a specific anime
  Future<Directory> getAnimeDir(String animeId, String animeTitle) async {
    final base = await downloadsDir;
    final sanitized = _sanitizeFilename(animeTitle);
    final dir = Directory(path.join(base.path, sanitized));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  
  /// Get the path for a specific episode file
  String getEpisodePath(Directory animeDir, int episodeNumber, String category) {
    return path.join(animeDir.path, 'ep${episodeNumber}_$category.mp4');
  }
  
  /// Get the path for episode metadata
  String getEpisodeMetaPath(Directory animeDir, int episodeNumber, String category) {
    return path.join(animeDir.path, 'ep${episodeNumber}_$category.json');
  }
  
  /// Check if an episode is downloaded for the current profile
  Future<CachedEpisode?> getCachedEpisode(
    String animeId, 
    String animeTitle,
    int episodeNumber, 
    String category, // 'sub' or 'dub'
  ) async {
    final animeDir = await getAnimeDir(animeId, animeTitle);
    final filePath = getEpisodePath(animeDir, episodeNumber, category);
    final file = File(filePath);
    
    if (await file.exists()) {
      final stat = await file.stat();
      if (stat.size > 1024 * 1024) { // At least 1MB to be valid
        // Try to read subtitle paths from metadata
        List<Map<String, String>> subtitles = [];
        final metaPath = getEpisodeMetaPath(animeDir, episodeNumber, category);
        final metaFile = File(metaPath);
        if (await metaFile.exists()) {
          try {
            final meta = jsonDecode(await metaFile.readAsString());
            if (meta['subtitles'] != null) {
              subtitles = (meta['subtitles'] as List)
                  .map((s) => Map<String, String>.from(s as Map))
                  .toList();
            }
          } catch (e) {
            debugPrint('Failed to read subtitle metadata: $e');
          }
        }
        
        return CachedEpisode(
          animeId: animeId,
          animeTitle: animeTitle,
          episodeNumber: episodeNumber,
          category: category,
          filePath: filePath,
          fileSize: stat.size,
          downloadedAt: stat.modified,
          profileId: _currentProfileId,
          subtitles: subtitles,
        );
      }
    }
    return null;
  }
  
  /// Get all cached episodes for an anime (current profile)
  Future<List<CachedEpisode>> getCachedEpisodesForAnime(
    String animeId, 
    String animeTitle,
  ) async {
    final animeDir = await getAnimeDir(animeId, animeTitle);
    final episodes = <CachedEpisode>[];
    
    if (!await animeDir.exists()) return episodes;
    
    await for (final entity in animeDir.list()) {
      if (entity is File && entity.path.endsWith('.mp4')) {
        final filename = path.basename(entity.path);
        final match = RegExp(r'ep(\d+)_(sub|dub)\.mp4').firstMatch(filename);
        if (match != null) {
          final stat = await entity.stat();
          final epNum = int.parse(match.group(1)!);
          final cat = match.group(2)!;
          
          // Try to read subtitle paths from metadata
          List<Map<String, String>> subtitles = [];
          final metaPath = getEpisodeMetaPath(animeDir, epNum, cat);
          final metaFile = File(metaPath);
          if (await metaFile.exists()) {
            try {
              final meta = jsonDecode(await metaFile.readAsString());
              if (meta['subtitles'] != null) {
                subtitles = (meta['subtitles'] as List)
                    .map((s) => Map<String, String>.from(s as Map))
                    .toList();
              }
            } catch (e) {
              debugPrint('Failed to read subtitle metadata: $e');
            }
          }
          
          episodes.add(CachedEpisode(
            animeId: animeId,
            animeTitle: animeTitle,
            episodeNumber: epNum,
            category: cat,
            filePath: entity.path,
            fileSize: stat.size,
            downloadedAt: stat.modified,
            profileId: _currentProfileId,
            subtitles: subtitles,
          ));
        }
      }
    }
    
    episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return episodes;
  }
  
  /// Get all downloaded anime with their episodes (current profile)
  Future<List<DownloadedAnime>> getAllDownloadedAnime() async {
    final base = await downloadsDir;
    final animeList = <DownloadedAnime>[];
    
    if (!await base.exists()) return animeList;
    
    await for (final entity in base.list()) {
      if (entity is Directory) {
        final metaFile = File(path.join(entity.path, 'meta.json'));
        String? animeId;
        String? title;
        String? coverImage;
        
        if (await metaFile.exists()) {
          try {
            final meta = jsonDecode(await metaFile.readAsString());
            animeId = meta['animeId'];
            title = meta['title'];
            coverImage = meta['coverImage'];
          } catch (_) {}
        }
        
        title ??= path.basename(entity.path);
        animeId ??= title.toLowerCase().replaceAll(' ', '-');
        
        // At this point title and animeId are guaranteed non-null
        final safeAnimeId = animeId;
        final safeTitle = title;
        
        final episodes = <CachedEpisode>[];
        await for (final file in entity.list()) {
          if (file is File && file.path.endsWith('.mp4')) {
            final filename = path.basename(file.path);
            final match = RegExp(r'ep(\d+)_(sub|dub)\.mp4').firstMatch(filename);
            if (match != null) {
              final stat = await file.stat();
              final epNum = int.parse(match.group(1)!);
              final cat = match.group(2)!;
              
              // Try to read subtitle paths from metadata
              List<Map<String, String>> subtitles = [];
              final metaPath = getEpisodeMetaPath(entity, epNum, cat);
              final metaFile = File(metaPath);
              if (await metaFile.exists()) {
                try {
                  final meta = jsonDecode(await metaFile.readAsString());
                  if (meta['subtitles'] != null) {
                    subtitles = (meta['subtitles'] as List)
                        .map((s) => Map<String, String>.from(s as Map))
                        .toList();
                  }
                } catch (e) {
                  debugPrint('Failed to read subtitle metadata: $e');
                }
              }
              
              episodes.add(CachedEpisode(
                animeId: safeAnimeId,
                animeTitle: safeTitle,
                episodeNumber: epNum,
                category: cat,
                filePath: file.path,
                fileSize: stat.size,
                downloadedAt: stat.modified,
                profileId: _currentProfileId,
                subtitles: subtitles,
              ));
            }
          }
        }
        
        if (episodes.isNotEmpty) {
          episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          animeList.add(DownloadedAnime(
            animeId: safeAnimeId,
            title: safeTitle,
            coverImage: coverImage,
            episodes: episodes,
            profileId: _currentProfileId,
          ));
        }
      }
    }
    
    animeList.sort((a, b) => a.title.compareTo(b.title));
    return animeList;
  }
  
  /// Download an episode for the current profile
  Future<CachedEpisode?> downloadEpisode({
    required String animeId,
    required String animeTitle,
    required String episodeId,
    required int episodeNumber,
    required String category,
    String? coverImage,
    Function(double progress, String status)? onProgress,
  }) async {
    final profileId = _currentProfileId;
    final taskId = '${profileId}_${animeId}_${episodeNumber}_$category';
    
    // Check if already downloading
    if (_activeDownloads.containsKey(taskId)) {
      debugPrint('Episode already downloading: $taskId');
      return null;
    }
    
    final task = DownloadTask(
      animeId: animeId,
      animeTitle: animeTitle,
      episodeNumber: episodeNumber,
      category: category,
      profileId: profileId,
    );
    _activeDownloads[taskId] = task;
    _notifyListeners(task);
    
    try {
      // Get streaming URL
      task.status = 'Fetching stream...';
      _notifyListeners(task);
      onProgress?.call(0, task.status);
      
      final streamingData = await _aniwatchService.getStreamingSources(
        episodeId, 
        category: category,
      );
      
      if (streamingData == null || streamingData.sources.isEmpty) {
        throw Exception('No streaming sources found');
      }
      
      final videoUrl = streamingData.sources.first.url;
      final referer = streamingData.referer ?? 'https://megacloud.blog/';
      
      // Create anime directory and save metadata
      final animeDir = await getAnimeDir(animeId, animeTitle);
      await _saveAnimeMetadata(animeDir, animeId, animeTitle, coverImage);
      
      final outputPath = getEpisodePath(animeDir, episodeNumber, category);
      
      // Use HTTP download on mobile platforms, yt-dlp on desktop
      if (Platform.isAndroid || Platform.isIOS) {
        // HTTP-based download for mobile
        await _downloadWithHttp(
          videoUrl: videoUrl,
          outputPath: outputPath,
          referer: referer,
          task: task,
          onProgress: onProgress,
        );
      } else {
        // Download with yt-dlp on desktop
        await _downloadWithYtDlp(
          videoUrl: videoUrl,
          outputPath: outputPath,
          referer: referer,
          task: task,
          onProgress: onProgress,
        );
      }
      
      // Verify download
      final file = File(outputPath);
      if (!await file.exists()) {
        throw Exception('Download failed - file not found');
      }
      
      final stat = await file.stat();
      if (stat.size < 1024 * 1024) {
        await file.delete();
        throw Exception('Download incomplete - file too small');
      }

      // Download subtitles
      final subtitleFiles = <Map<String, String>>[];
      if (streamingData.subtitles.isNotEmpty) {
        task.status = 'Downloading subtitles...';
        _notifyListeners(task);
        
        for (int i = 0; i < streamingData.subtitles.length; i++) {
          final subtitle = streamingData.subtitles[i];
          try {
            // Create subtitle file path
            final sanitizedLang = _sanitizeFilename(subtitle.lang);
            final subtitlePath = path.join(
              animeDir.path,
              'ep${episodeNumber}_${category}_$sanitizedLang.vtt',
            );
            
            // Download subtitle file
            final response = await http.get(Uri.parse(subtitle.url));
            if (response.statusCode == 200) {
              await File(subtitlePath).writeAsBytes(response.bodyBytes);
              subtitleFiles.add({
                'filePath': subtitlePath,
                'lang': subtitle.lang,
              });
              debugPrint('Downloaded subtitle: ${subtitle.lang} -> $subtitlePath');
            }
          } catch (e) {
            debugPrint('Failed to download subtitle ${subtitle.lang}: $e');
            // Continue with other subtitles
          }
        }
      }
      
      onProgress?.call(1.0, 'Complete');
      
      task.progress = 1.0;
      task.status = 'Complete';
      task.isComplete = true;
      _notifyListeners(task);
      
      // Save episode metadata with subtitle paths
      await _saveEpisodeMetadata(
        animeDir,
        episodeNumber,
        category,
        subtitleFiles,
      );
      
      return CachedEpisode(
        animeId: animeId,
        animeTitle: animeTitle,
        episodeNumber: episodeNumber,
        category: category,
        filePath: outputPath,
        fileSize: stat.size,
        downloadedAt: DateTime.now(),
        profileId: profileId,
        subtitles: subtitleFiles,
      );
      
    } catch (e) {
      task.status = 'Error: $e';
      task.error = e.toString();
      _notifyListeners(task);
      onProgress?.call(0, task.status);
      rethrow;
    } finally {
      _activeDownloads.remove(taskId);
    }
  }
  
  /// Delete a cached episode
  Future<bool> deleteEpisode(CachedEpisode episode) async {
    try {
      final file = File(episode.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('Failed to delete episode: $e');
      return false;
    }
  }
  
  /// Delete multiple episodes
  Future<int> deleteEpisodes(List<CachedEpisode> episodes) async {
    int deleted = 0;
    for (final episode in episodes) {
      if (await deleteEpisode(episode)) {
        deleted++;
      }
    }
    return deleted;
  }
  
  /// Delete all episodes for an anime
  Future<bool> deleteAnime(String animeId, String animeTitle) async {
    try {
      final animeDir = await getAnimeDir(animeId, animeTitle);
      if (await animeDir.exists()) {
        await animeDir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('Failed to delete anime: $e');
      return false;
    }
  }
  
  /// Get total download size for current profile
  Future<int> getTotalDownloadSize() async {
    int total = 0;
    final anime = await getAllDownloadedAnime();
    for (final a in anime) {
      for (final ep in a.episodes) {
        total += ep.fileSize;
      }
    }
    return total;
  }
  
  /// Add progress listener
  void addProgressListener(Function(DownloadTask) listener) {
    _progressListeners.add(listener);
  }
  
  /// Remove progress listener
  void removeProgressListener(Function(DownloadTask) listener) {
    _progressListeners.remove(listener);
  }
  
  void _notifyListeners(DownloadTask task) {
    for (final listener in _progressListeners) {
      listener(task);
    }
  }
  
  Future<void> _saveAnimeMetadata(
    Directory animeDir, 
    String animeId, 
    String title,
    String? coverImage,
  ) async {
    final metaFile = File(path.join(animeDir.path, 'meta.json'));
    await metaFile.writeAsString(jsonEncode({
      'animeId': animeId,
      'title': title,
      'coverImage': coverImage,
      'profileId': _currentProfileId,
      'updatedAt': DateTime.now().toIso8601String(),
    }));
  }
  
  /// Save episode-level metadata
  Future<void> _saveEpisodeMetadata(
    Directory animeDir,
    int episodeNumber,
    String category,
    List<Map<String, String>> subtitles,
  ) async {
    final metaPath = getEpisodeMetaPath(animeDir, episodeNumber, category);
    final metaFile = File(metaPath);
    await metaFile.writeAsString(jsonEncode({
      'episodeNumber': episodeNumber,
      'category': category,
      'profileId': _currentProfileId,
      'downloadedAt': DateTime.now().toIso8601String(),
      'subtitles': subtitles,
    }));
  }
  
  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
  
  /// Check if episode is currently downloading
  bool isDownloading(String animeId, int episodeNumber, String category) {
    final profileId = _currentProfileId;
    final taskId = '${profileId}_${animeId}_${episodeNumber}_$category';
    return _activeDownloads.containsKey(taskId);
  }
  
  /// Get active download task
  DownloadTask? getActiveDownload(String animeId, int episodeNumber, String category) {
    final profileId = _currentProfileId;
    final taskId = '${profileId}_${animeId}_${episodeNumber}_$category';
    return _activeDownloads[taskId];
  }
  
  /// Download video using HTTP (for mobile platforms)
  Future<void> _downloadWithHttp({
    required String videoUrl,
    required String outputPath,
    required String referer,
    required DownloadTask task,
    Function(double progress, String status)? onProgress,
  }) async {
    task.status = 'Downloading...';
    _notifyListeners(task);
    
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(videoUrl));
      request.headers['Referer'] = referer;
      request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
      
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      DateTime lastUpdate = DateTime.now();
      int lastBytes = 0;
      
      final file = File(outputPath);
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        if (contentLength > 0) {
          final now = DateTime.now();
          final elapsed = now.difference(lastUpdate).inMilliseconds;
          
          if (elapsed >= 500) { // Update every 500ms
            final bytesPerSecond = ((downloaded - lastBytes) * 1000 / elapsed).round();
            lastBytes = downloaded;
            lastUpdate = now;
            
            // Cap progress at 0.99 during download; 1.0 is set after verification
            task.progress = (downloaded / contentLength).clamp(0.0, 0.99);
            
            String speedText = '';
            if (bytesPerSecond > 1024 * 1024) {
              speedText = ' • ${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
            } else if (bytesPerSecond > 1024) {
              speedText = ' • ${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
            }
            
            task.status = 'Caching ${(task.progress * 100).toStringAsFixed(0)}%$speedText';
            _notifyListeners(task);
            onProgress?.call(task.progress, task.status);
          }
        }
      }
      
      await sink.close();
      
      // Stream completed successfully - set progress to 100%
      task.progress = 1.0;
      task.status = 'Caching 100%';
      _notifyListeners(task);
      onProgress?.call(1.0, 'Caching 100%');
      
      // Verify download
      final stat = await file.stat();
      if (stat.size < 1024 * 1024) {
        await file.delete();
        throw Exception('Download incomplete - file too small');
      }
    } finally {
      client.close();
    }
  }
  
  /// Download video using yt-dlp (for desktop platforms)
  Future<void> _downloadWithYtDlp({
    required String videoUrl,
    required String outputPath,
    required String referer,
    required DownloadTask task,
    Function(double progress, String status)? onProgress,
  }) async {
    task.status = 'Downloading...';
    _notifyListeners(task);
    
    final ytdlpPath = await BundledTools.findYtDlp();
    if (ytdlpPath == null) {
      throw Exception('yt-dlp not found');
    }
    
    final ffmpegPath = await BundledTools.findFfmpegDir();
    
    final args = [
      '--no-check-certificates',
      '--referer', referer,
      '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      '-f', 'best[ext=mp4]/best',
      '--no-warnings',
      '--newline',
      // Multithreaded download for faster speeds
      '--concurrent-fragments', '12',
      '--throttled-rate', '100K',
      '--retries', '10',
      '--fragment-retries', '10',
      '-o', outputPath,
    ];
    
    if (ffmpegPath != null && await Directory(ffmpegPath).exists()) {
      args.addAll(['--ffmpeg-location', ffmpegPath]);
    }
    
    args.add(videoUrl);
    
    final process = await Process.start(ytdlpPath, args);
    
    // Monitor progress - yt-dlp outputs like: "[download]  45.2% of 150.00MiB at  5.23MiB/s ETA 00:15"
    void parseProgress(String data) {
      final percentMatch = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(data);
      final speedMatch = RegExp(r'at\s+([\d.]+)([KMG]i?B)/s').firstMatch(data);
      
      if (percentMatch != null) {
        task.progress = double.parse(percentMatch.group(1)!) / 100;
        
        String speedText = '';
        if (speedMatch != null) {
          final speedNum = double.parse(speedMatch.group(1)!);
          final speedUnit = speedMatch.group(2)!;
          speedText = ' • ${speedNum.toStringAsFixed(1)} $speedUnit/s';
        }
        
        task.status = 'Caching ${(task.progress * 100).toStringAsFixed(0)}%$speedText';
        _notifyListeners(task);
        onProgress?.call(task.progress, task.status);
      }
    }
    
    process.stdout.transform(const SystemEncoding().decoder).listen(parseProgress);
    process.stderr.transform(const SystemEncoding().decoder).listen(parseProgress);
    
    final exitCode = await process.exitCode;
    
    if (exitCode != 0) {
      throw Exception('Download failed with exit code $exitCode');
    }
    
    // Process exited successfully - ensure progress shows 100%
    task.progress = 1.0;
    task.status = 'Caching 100%';
    _notifyListeners(task);
    onProgress?.call(1.0, 'Caching 100%');
    
    // Verify download
    final file = File(outputPath);
    if (!await file.exists()) {
      throw Exception('Download failed - file not found');
    }
    
    final stat = await file.stat();
    if (stat.size < 1024 * 1024) {
      await file.delete();
      throw Exception('Download incomplete - file too small');
    }
  }
}

/// Represents a cached/downloaded episode
class CachedEpisode {
  final String animeId;
  final String animeTitle;
  final int episodeNumber;
  final String category; // 'sub' or 'dub'
  final String filePath;
  final int fileSize;
  final DateTime downloadedAt;
  final String profileId;
  final List<Map<String, String>> subtitles; // [{filePath: ..., lang: ...}]
  
  CachedEpisode({
    required this.animeId,
    required this.animeTitle,
    required this.episodeNumber,
    required this.category,
    required this.filePath,
    required this.fileSize,
    required this.downloadedAt,
    required this.profileId,
    this.subtitles = const [],
  });
  
  String get fileSizeFormatted {
    if (fileSize > 1024 * 1024 * 1024) {
      return '${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    } else if (fileSize > 1024 * 1024) {
      return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
  }
}

/// Represents a downloaded anime with its episodes
class DownloadedAnime {
  final String animeId;
  final String title;
  final String? coverImage;
  final List<CachedEpisode> episodes;
  final String profileId;
  
  DownloadedAnime({
    required this.animeId,
    required this.title,
    this.coverImage,
    required this.episodes,
    required this.profileId,
  });
  
  List<CachedEpisode> get subEpisodes => 
    episodes.where((e) => e.category == 'sub').toList();
  
  List<CachedEpisode> get dubEpisodes => 
    episodes.where((e) => e.category == 'dub').toList();
  
  int get totalSize => episodes.fold(0, (sum, ep) => sum + ep.fileSize);
  
  String get totalSizeFormatted {
    if (totalSize > 1024 * 1024 * 1024) {
      return '${(totalSize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    } else if (totalSize > 1024 * 1024) {
      return '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    }
  }
}

/// Represents an active download task
class DownloadTask {
  final String animeId;
  final String animeTitle;
  final int episodeNumber;
  final String category;
  final String profileId;
  double progress = 0.0;
  String status = 'Starting...';
  bool isComplete = false;
  String? error;
  
  DownloadTask({
    required this.animeId,
    required this.animeTitle,
    required this.episodeNumber,
    required this.category,
    required this.profileId,
  });
  
  String get taskId => '${profileId}_${animeId}_${episodeNumber}_$category';
}
