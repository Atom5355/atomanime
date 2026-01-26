import 'dart:io';
import 'package:path/path.dart' as path;

/// Utility class to find bundled tools (yt-dlp, ffmpeg) in both
/// development and production/installed environments.
class BundledTools {
  static String? _cachedExeDir;
  static String? _cachedDevDir;
  
  /// Get the directory where the executable is located (for production)
  static String get exeDir {
    _cachedExeDir ??= path.dirname(Platform.resolvedExecutable);
    return _cachedExeDir!;
  }
  
  /// Get the development directory (current working directory)
  static String get devDir {
    _cachedDevDir ??= Directory.current.path;
    return _cachedDevDir!;
  }
  
  /// Check if running in development mode (flutter run)
  static bool get isDevelopment {
    // In development, the exe is in a flutter cache folder
    return Platform.resolvedExecutable.contains('flutter') ||
           Platform.resolvedExecutable.contains('.pub-cache');
  }
  
  /// Find yt-dlp executable
  static Future<String?> findYtDlp() async {
    final possiblePaths = [
      // Production/installed paths (relative to exe) - check first
      path.join(exeDir, 'tools', 'yt-dlp', 'yt-dlp.exe'),
      // Development paths
      path.join(devDir, 'assets', 'yt-dlp', 'yt-dlp.exe'),
      // Other production paths
      path.join(exeDir, 'yt-dlp', 'yt-dlp.exe'),
      path.join(exeDir, 'data', 'flutter_assets', 'assets', 'yt-dlp', 'yt-dlp.exe'),
      // System PATH
      'yt-dlp',
    ];
    
    for (final p in possiblePaths) {
      if (p == 'yt-dlp') {
        // Check if available in PATH
        try {
          final result = await Process.run('yt-dlp', ['--version']);
          if (result.exitCode == 0) return 'yt-dlp';
        } catch (_) {}
      } else if (await File(p).exists()) {
        return p;
      }
    }
    
    return null;
  }
  
  /// Find ffmpeg executable
  static Future<String?> findFfmpeg() async {
    final possiblePaths = [
      // Production/installed paths - check first
      path.join(exeDir, 'tools', 'ffmpeg', 'bin', 'ffmpeg.exe'),
      // Development paths
      path.join(devDir, 'assets', 'ffmpeg', 'ffmpeg-master-latest-win64-gpl', 'bin', 'ffmpeg.exe'),
      // Other production paths
      path.join(exeDir, 'ffmpeg', 'bin', 'ffmpeg.exe'),
      path.join(exeDir, 'ffmpeg', 'ffmpeg.exe'),
      path.join(exeDir, 'data', 'flutter_assets', 'assets', 'ffmpeg', 'ffmpeg-master-latest-win64-gpl', 'bin', 'ffmpeg.exe'),
      // System PATH
      'ffmpeg',
    ];
    
    for (final p in possiblePaths) {
      if (p == 'ffmpeg') {
        try {
          final result = await Process.run('ffmpeg', ['-version']);
          if (result.exitCode == 0) return 'ffmpeg';
        } catch (_) {}
      } else if (await File(p).exists()) {
        return p;
      }
    }
    
    return null;
  }
  
  /// Find ffmpeg directory (for --ffmpeg-location)
  static Future<String?> findFfmpegDir() async {
    final ffmpegPath = await findFfmpeg();
    if (ffmpegPath == null || ffmpegPath == 'ffmpeg') return null;
    return path.dirname(ffmpegPath);
  }
}
