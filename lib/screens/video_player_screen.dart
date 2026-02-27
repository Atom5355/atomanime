import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'dart:io';
import '../models/episode.dart';
import '../providers/anime_provider.dart';
import '../services/download_cache_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvInputDetector;

class VideoPlayerScreen extends StatefulWidget {
  final String episodeId;
  final String episodeTitle;
  final String category;
  final int? episodeNumber;
  final String? localFilePath; // For playing cached downloads
  final String? animeId; // For cache lookup
  final String? animeTitle; // For cache lookup
  final String? coverImage; // Anime cover image for watch history

  const VideoPlayerScreen({
    super.key,
    required this.episodeId,
    required this.episodeTitle,
    this.category = 'sub',
    this.episodeNumber,
    this.localFilePath,
    this.animeId,
    this.animeTitle,
    this.coverImage,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  late final FocusNode _focusNode;
  StreamingData? _streamingData;
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedSourceIndex = 0;
  int _selectedSubtitleIndex = -1; // -1 = off
  bool _isDisposed = false;
  bool _showSettings = false;
  double _playbackSpeed = 1.0;
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _hideControlsTimer;
  
  // Watch progress tracking
  Timer? _progressTimer;
  Duration _lastSavedPosition = Duration.zero;
  Duration? _resumePosition;
  bool _hasResumed = false;
  
  // Resume tooltip
  bool _showResumeTooltip = false;
  double _resumeTooltipProgress = 0.0;
  Timer? _resumeTooltipTimer;
  
  // Autoplay next episode
  bool _showAutoplayOverlay = false;
  int _autoplayCountdown = 15; // Reduced to 15 seconds since it triggers later
  Timer? _autoplayTimer;
  bool _autoplayCancelled = false;
  bool _isPlayingNextEpisode = false; // Prevents re-triggering autoplay during download
  Episode? _nextEpisode;
  bool _isLoadingNextEpisode = false;
  
  // D-Pad/TV navigation focus
  int _focusedControlIndex = 1; // 0=rewind, 1=play/pause, 2=forward, 3=settings, 4=fullscreen
  bool _isSeekMode = false; // When true, left/right seeks instead of changing focus
  static const int _totalControls = 5;

  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    // Create player with optimal configuration for RTX VSR support
    // These settings are applied at creation time to avoid playback issues
    _player = Player(
      configuration: PlayerConfiguration(
        // Title for window managers
        title: 'ATOM ANIME',
        // Buffer size for smooth streaming
        bufferSize: 128 * 1024 * 1024, // 128MB buffer for smoother playback
      ),
    );
    // Configure VideoController with platform-specific settings
    // On Android, use hardware acceleration for proper video rendering
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // Enable hardware acceleration on all platforms
        enableHardwareAcceleration: true,
        // Use Android surface texture for proper video display with Impeller
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    _focusNode = FocusNode();
    
    // Initialize video enhancement (set mpv properties before video loads)
    _initializeVideoEnhancement();
    
    // Only allow landscape on TV to prevent crashes
    // On mobile, allow portrait as well
    if (Platform.isAndroid) {
      final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
      final isLargeScreen = size.shortestSide > 600 * WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      if (isLargeScreen) {
        // TV mode - landscape only
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ]);
      } else {
        // Mobile - allow portrait too
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.portraitUp,
        ]);
      }
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
      ]);
    }
    
    // Load resume position FIRST, then load streaming data
    _initializePlayback();
    _startHideControlsTimer();
    
    // Start progress tracking timer (save every 10 seconds)
    _startProgressTracking();
  }

  /// Load resume position first, then start playback
  Future<void> _initializePlayback() async {
    await _loadResumePosition();
    _loadStreamingData();
  }

  Future<void> _loadResumePosition() async {
    if (widget.animeId == null || widget.episodeNumber == null) return;
    
    try {
      final profileService = ProfileService();
      if (!profileService.isLoggedIn) return;
      
      _resumePosition = await profileService.getResumePosition(
        animeId: widget.animeId!,
        episodeNumber: widget.episodeNumber!,
        category: widget.category,
      );
      
      if (_resumePosition != null) {
        debugPrint('Resume position found: ${_resumePosition!.inSeconds}s');
      }
    } catch (e) {
      debugPrint('Error loading resume position: $e');
    }
  }

  void _startProgressTracking() {
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Save progress (throttled by _saveWatchProgress internally)
      _saveWatchProgress();
      // Check for autoplay trigger
      _checkAutoplayTrigger();
    });
  }

  /// Check if we should show autoplay overlay (1 minute before end)
  void _checkAutoplayTrigger() {
    if (_isDisposed || _autoplayCancelled || _showAutoplayOverlay || _isPlayingNextEpisode) return;
    if (widget.animeId == null || widget.episodeNumber == null) return;
    
    final position = _player.state.position;
    final duration = _player.state.duration;
    
    if (duration <= Duration.zero) return;
    
    final remaining = duration - position;
    const triggerThreshold = Duration(minutes: 1); // Last 1 minute
    
    // Trigger when 1 minute or less remaining
    if (remaining <= triggerThreshold && remaining > Duration.zero) {
      _triggerAutoplayOverlay();
    }
  }

  /// Start the autoplay overlay and countdown
  void _triggerAutoplayOverlay() async {
    if (_showAutoplayOverlay || _autoplayCancelled) return;
    
    // Fetch next episode info
    if (_nextEpisode == null && !_isLoadingNextEpisode) {
      _isLoadingNextEpisode = true;
      try {
        final provider = Provider.of<AnimeProvider>(context, listen: false);
        await provider.loadEpisodes(widget.animeId!);
        
        final episodes = provider.episodes;
        final currentNumber = widget.episodeNumber!;
        
        // Find next episode
        _nextEpisode = episodes.firstWhere(
          (e) => e.number == currentNumber + 1,
          orElse: () => Episode(id: '', number: 0),
        );
        
        // If no next episode found (id is empty), don't show overlay
        if (_nextEpisode!.id.isEmpty) {
          _nextEpisode = null;
          _isLoadingNextEpisode = false;
          return;
        }
      } catch (e) {
        debugPrint('Error fetching next episode: $e');
        _isLoadingNextEpisode = false;
        return;
      }
      _isLoadingNextEpisode = false;
    }
    
    if (_nextEpisode == null) return;
    
    setState(() {
      _showAutoplayOverlay = true;
      _autoplayCountdown = 15; // 15 seconds since it triggers at last minute
    });
    
    // Start countdown timer
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || _autoplayCancelled) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _autoplayCountdown--;
      });
      
      if (_autoplayCountdown <= 0) {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  /// Cancel autoplay
  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    setState(() {
      _showAutoplayOverlay = false;
      _autoplayCancelled = true;
    });
  }

  /// Play next episode immediately
  void _playNextEpisode() async {
    if (_nextEpisode == null || widget.animeId == null) return;
    
    _autoplayTimer?.cancel();
    _isPlayingNextEpisode = true; // Prevent autoplay from re-triggering
    setState(() {
      _showAutoplayOverlay = false;
    });
    
    // Pause current video
    _player.pause();
    
    // Save current progress as completed
    await _saveWatchProgress();
    
    if (!mounted) return;
    
    // On mobile, skip caching and navigate directly to stream
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    if (isMobile) {
      // Navigate directly to next episode (will stream)
      debugPrint('Mobile: Navigating to next episode without caching');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            episodeId: _nextEpisode!.id,
            episodeTitle: _nextEpisode!.title ?? 'Episode ${_nextEpisode!.number}',
            category: widget.category,
            episodeNumber: _nextEpisode!.number,
            animeId: widget.animeId,
            animeTitle: widget.animeTitle,
            coverImage: widget.coverImage,
            localFilePath: null, // Stream directly
          ),
        ),
      );
      return;
    }
    
    // Desktop: Use caching system
    final cacheService = DownloadCacheService();
    
    // Check if already cached
    final existingCached = await cacheService.getCachedEpisode(
      widget.animeId!,
      widget.animeTitle ?? 'Unknown',
      _nextEpisode!.number,
      widget.category,
    );
    
    String? localFilePath;
    
    if (existingCached != null) {
      // Already cached, use it directly
      debugPrint('Next episode already cached: ${existingCached.filePath}');
      localFilePath = existingCached.filePath;
    } else {
      // Show download dialog
      debugPrint('Showing download dialog for Episode ${_nextEpisode!.number}');
      
      if (!mounted) return;
      
      final result = await showDialog<CachedEpisode?>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _AutoplayDownloadDialog(
          animeTitle: widget.animeTitle ?? 'Unknown',
          episodeNumber: _nextEpisode!.number,
          category: widget.category,
          onDownload: (onProgress) async {
            return await cacheService.downloadEpisode(
              animeId: widget.animeId!,
              animeTitle: widget.animeTitle ?? 'Unknown',
              episodeId: _nextEpisode!.id,
              episodeNumber: _nextEpisode!.number,
              category: widget.category,
              coverImage: widget.coverImage,
              onProgress: onProgress,
            );
          },
        ),
      );
      
      debugPrint('Download dialog result: $result');
      
      if (result == null) {
        // Download was cancelled or failed - resume current video
        debugPrint('Download cancelled or failed, resuming current video');
        if (mounted) {
          _player.play();
          setState(() {
            _autoplayCancelled = true; // Don't trigger autoplay again
          });
        }
        return;
      }
      
      localFilePath = result.filePath;
    }
    
    // Navigate to next episode
    if (mounted) {
      debugPrint('Navigating to next episode with file: $localFilePath');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            episodeId: _nextEpisode!.id,
            episodeTitle: _nextEpisode!.title ?? 'Episode ${_nextEpisode!.number}',
            category: widget.category, // Keep same language (sub/dub)
            episodeNumber: _nextEpisode!.number,
            animeId: widget.animeId,
            animeTitle: widget.animeTitle,
            coverImage: widget.coverImage,
            localFilePath: localFilePath,
          ),
        ),
      );
    }
  }

  Future<void> _saveWatchProgress() async {
    if (widget.animeId == null || widget.episodeNumber == null) return;
    if (_isDisposed) return;
    
    final profileService = ProfileService();
    if (!profileService.isLoggedIn) return;
    
    final position = _player.state.position;
    final duration = _player.state.duration;
    
    // Only save if we've progressed more than 5 seconds since last save
    if ((position - _lastSavedPosition).abs() < const Duration(seconds: 5)) {
      return;
    }
    
    if (position > Duration.zero && duration > Duration.zero) {
      _lastSavedPosition = position;
      
      await profileService.updateWatchProgress(
        animeId: widget.animeId!,
        animeTitle: widget.animeTitle ?? 'Unknown',
        coverImage: widget.coverImage,
        episodeNumber: widget.episodeNumber!,
        episodeId: widget.episodeId,
        category: widget.category,
        watchedDuration: position,
        totalDuration: duration,
      );
      debugPrint('Saved watch progress: ${position.inSeconds}/${duration.inSeconds}s');
    }
  }

  Future<void> _initializeVideoEnhancement() async {
    if (!Platform.isWindows) return;
    
    try {
      final nativePlayer = _player.platform as dynamic;
      
      // === HARDWARE DECODING ===
      // Use d3d11va for GPU-accelerated decode (offloads CPU, prevents decode lag)
      await nativePlayer.setProperty('hwdec', 'd3d11va');
      await nativePlayer.setProperty('hwdec-codecs', 'all');
      
      // === PERFORMANCE OPTIMIZATIONS ===
      // Force D3D11 rendering API (avoid OpenGL performance issues on Windows)
      await nativePlayer.setProperty('gpu-api', 'd3d11');
      // High priority process for smoother playback under load
      await nativePlayer.setProperty('priority', 'high');
      // Enable Pixel Buffer Objects for faster texture uploads
      await nativePlayer.setProperty('opengl-pbo', 'yes');
      
      // === THE JUDDER FIX: Display Sync + Interpolation ===
      // Lock video timing to display refresh rate (eliminates frame drops/dupes)
      await nativePlayer.setProperty('video-sync', 'display-resample');
      // Allow up to 5% speed adjustment to match display refresh
      await nativePlayer.setProperty('video-sync-max-video-change', '5');
      // Auto-detect display refresh rate
      await nativePlayer.setProperty('override-display-fps', '0');
      
      // === MOTION INTERPOLATION (Smooth Panning) ===
      await nativePlayer.setProperty('interpolation', 'yes');
      // Mitchell-Netravali filter: high-quality, sharp interpolation
      await nativePlayer.setProperty('tscale', 'mitchell');
      // Sphinx window for smoother motion with minimal artifacts
      await nativePlayer.setProperty('tscale-window', 'sphinx');
      await nativePlayer.setProperty('tscale-radius', '1.05');
      await nativePlayer.setProperty('tscale-clamp', '0.0');
      await nativePlayer.setProperty('tscale-antiring', '0.7');
      
      // === VISUAL QUALITY ===
      // Temporal dithering: smoother gradients, reduces banding perception
      await nativePlayer.setProperty('temporal-dither', 'yes');
      
      // Debanding filter (essential for anime gradients)
      await nativePlayer.setProperty('deband', 'yes');
      await nativePlayer.setProperty('deband-iterations', '2');
      await nativePlayer.setProperty('deband-threshold', '35');
      await nativePlayer.setProperty('deband-range', '16');
      
      // === BUFFERING (Prevent IO Hiccups) ===
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', '30'); // 30 seconds buffer
      await nativePlayer.setProperty('demuxer-max-bytes', '256M');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '128M');
      
      // === SUBTITLE RENDERING ===
      // Blend subtitles with interpolated frames for smooth motion
      await nativePlayer.setProperty('blend-subtitles', 'yes');
      
      debugPrint('Video enhancement initialized: d3d11va hwdec, display-resample, mitchell interpolation (judder-free anime)');
    } catch (e) {
      debugPrint('Video enhancement init error: $e');
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _autoplayTimer?.cancel();
    _resumeTooltipTimer?.cancel();
    
    // Save final watch progress before disposing
    _saveWatchProgress();
    
    _focusNode.dispose();
    // On TV, keep landscape orientation to prevent crashes
    // On mobile, reset to portrait
    if (Platform.isAndroid) {
      final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
      final isLargeScreen = size.shortestSide > 600 * WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      if (isLargeScreen) {
        // TV mode - stay in landscape
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ]);
      } else {
        // Mobile - reset to portrait
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    _player.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final key = event.logicalKey;
    
    // Detect D-Pad input (suggests TV or controller usage)
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      TvInputDetector.instance.onDpadInput();
    }
    
    // If controls are hidden, any D-Pad input shows them first
    if (!_showControls && !_showSettings) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select) {
        _onUserInteraction();
        return KeyEventResult.handled;
      }
    }
    
    // When controls are visible, handle D-Pad navigation
    if (_showControls && !_showSettings) {
      // Left/Right - Seek or navigate controls based on mode
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_isSeekMode) {
          // Seek mode: left seeks backward
          final currentPos = _player.state.position;
          final newPos = currentPos - const Duration(seconds: 10);
          _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
        } else {
          // Navigation mode: move focus left
          setState(() {
            _focusedControlIndex = (_focusedControlIndex - 1).clamp(0, _totalControls - 1);
          });
        }
        _onUserInteraction();
        return KeyEventResult.handled;
      }
      
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_isSeekMode) {
          // Seek mode: right seeks forward
          final currentPos = _player.state.position;
          final duration = _player.state.duration;
          final newPos = currentPos + const Duration(seconds: 10);
          _player.seek(newPos > duration ? duration : newPos);
        } else {
          // Navigation mode: move focus right
          setState(() {
            _focusedControlIndex = (_focusedControlIndex + 1).clamp(0, _totalControls - 1);
          });
        }
        _onUserInteraction();
        return KeyEventResult.handled;
      }
      
      // Up - Toggle seek mode or adjust volume
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_isSeekMode) {
          // Exit seek mode
          setState(() => _isSeekMode = false);
        } else {
          // Volume up
          final currentVolume = _player.state.volume;
          _player.setVolume((currentVolume + 10).clamp(0, 100));
        }
        _onUserInteraction();
        return KeyEventResult.handled;
      }
      
      // Down - Enter seek mode or adjust volume  
      if (key == LogicalKeyboardKey.arrowDown) {
        if (!_isSeekMode) {
          // Enter seek mode when pressing down on play/pause
          if (_focusedControlIndex == 1) {
            setState(() => _isSeekMode = true);
          } else {
            // Volume down
            final currentVolume = _player.state.volume;
            _player.setVolume((currentVolume - 10).clamp(0, 100));
          }
        }
        _onUserInteraction();
        return KeyEventResult.handled;
      }
      
      // Enter/Select - Activate focused control
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
        if (_isSeekMode) {
          // Exit seek mode on confirm
          setState(() => _isSeekMode = false);
        } else {
          _activateFocusedControl();
        }
        _onUserInteraction();
        return KeyEventResult.handled;
      }
    }
    
    // Space - Always Play/Pause
    if (key == LogicalKeyboardKey.space) {
      _player.playOrPause();
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // Media Play/Pause/PlayPause
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.mediaPlay) {
      _player.play();
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.mediaPause) {
      _player.pause();
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // Media Rewind/FastForward (always seeks, ignores mode)
    if (key == LogicalKeyboardKey.mediaRewind) {
      final currentPos = _player.state.position;
      final newPos = currentPos - const Duration(seconds: 10);
      _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.mediaFastForward) {
      final currentPos = _player.state.position;
      final duration = _player.state.duration;
      final newPos = currentPos + const Duration(seconds: 10);
      _player.seek(newPos > duration ? duration : newPos);
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // Media Track Next - Skip to next episode if available
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (_nextEpisode != null) {
        _playNextEpisode();
      }
      return KeyEventResult.handled;
    }
    
    // Volume keys (hardware)
    if (key == LogicalKeyboardKey.audioVolumeUp) {
      final currentVolume = _player.state.volume;
      _player.setVolume((currentVolume + 10).clamp(0, 100));
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.audioVolumeDown) {
      final currentVolume = _player.state.volume;
      _player.setVolume((currentVolume - 10).clamp(0, 100));
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    if (key == LogicalKeyboardKey.audioVolumeMute) {
      final currentVolume = _player.state.volume;
      _player.setVolume(currentVolume > 0 ? 0 : 100);
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // C - Toggle subtitles
    if (key == LogicalKeyboardKey.keyC) {
      _toggleSubtitles();
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // F - Toggle fullscreen (desktop only)
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    
    // M - Mute toggle
    if (key == LogicalKeyboardKey.keyM) {
      final currentVolume = _player.state.volume;
      _player.setVolume(currentVolume > 0 ? 0 : 100);
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    
    // Escape or Back button - Close settings, exit seek mode, exit fullscreen, or exit player
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_isSeekMode) {
        setState(() => _isSeekMode = false);
      } else if (_showSettings) {
        setState(() => _showSettings = false);
      } else if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    
    // Media Stop - Exit player
    if (key == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
  
  /// Activate the currently focused control button
  void _activateFocusedControl() {
    switch (_focusedControlIndex) {
      case 0: // Rewind
        final newPosition = _player.state.position - const Duration(seconds: 10);
        _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
        break;
      case 1: // Play/Pause
        _player.playOrPause();
        break;
      case 2: // Forward
        final newPosition = _player.state.position + const Duration(seconds: 10);
        _player.seek(newPosition);
        break;
      case 3: // Settings
        setState(() => _showSettings = !_showSettings);
        break;
      case 4: // Fullscreen (desktop only)
        if (Platform.isWindows) _toggleFullscreen();
        break;
    }
  }

  void _toggleSubtitles() {
    if (_streamingData == null || _streamingData!.subtitles.isEmpty) return;
    
    if (_selectedSubtitleIndex >= 0) {
      // Subtitles are on, turn them off
      _changeSubtitle(-1);
    } else {
      // Subtitles are off, turn on first English or first available
      int newIndex = 0;
      for (int i = 0; i < _streamingData!.subtitles.length; i++) {
        if (_streamingData!.subtitles[i].lang.toLowerCase().contains('english')) {
          newIndex = i;
          break;
        }
      }
      _changeSubtitle(newIndex);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (Platform.isWindows) {
      try {
        final isCurrentlyFullscreen = await windowManager.isFullScreen();
        final newFullscreenState = !isCurrentlyFullscreen;
        
        // Update state first
        setState(() {
          _isFullscreen = newFullscreenState;
        });
        
        // Then toggle fullscreen with a slight delay to avoid conflicts with video rendering
        await Future.delayed(const Duration(milliseconds: 50));
        await windowManager.setFullScreen(newFullscreenState);
        
        _onUserInteraction();
      } catch (e) {
        debugPrint('Fullscreen toggle error: $e');
        // Revert state on error
        setState(() {
          _isFullscreen = !_isFullscreen;
        });
      }
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_showSettings) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onUserInteraction() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  Future<void> _loadStreamingData() async {
    try {
      // Always try to load subtitle metadata from cache if we have the info
      if (widget.animeId != null && widget.animeTitle != null && widget.episodeNumber != null) {
        final cacheService = DownloadCacheService();
        final cached = await cacheService.getCachedEpisode(
          widget.animeId!,
          widget.animeTitle!,
          widget.episodeNumber!,
          widget.category,
        );
        
        if (cached != null) {
          debugPrint('Found cached episode with ${cached.subtitles.length} subtitles');
          
          // Create StreamingData for cached subtitles
          if (cached.subtitles.isNotEmpty) {
            final cachedSubtitles = cached.subtitles.map((sub) {
              return SubtitleInfo(
                url: sub['filePath']!,
                lang: sub['lang']!,
                isDefault: false,
              );
            }).toList();
            
            if (mounted) {
              setState(() {
                _streamingData = StreamingData(
                  sources: [],
                  subtitles: cachedSubtitles,
                  referer: null,
                );
                
                // Auto-select first English subtitle if available
                for (int i = 0; i < cachedSubtitles.length; i++) {
                  if (cachedSubtitles[i].lang.toLowerCase().contains('english')) {
                    _selectedSubtitleIndex = i;
                    debugPrint('Auto-selected cached subtitle: ${cachedSubtitles[i].lang}');
                    break;
                  }
                }
                if (_selectedSubtitleIndex < 0 && cachedSubtitles.isNotEmpty) {
                  _selectedSubtitleIndex = 0; // Fallback to first subtitle
                  debugPrint('Auto-selected first cached subtitle: ${cachedSubtitles[0].lang}');
                }
              });
            }
          }
          
          // Use the cached file path (either from widget or from cache)
          final videoPath = widget.localFilePath ?? cached.filePath;
          debugPrint('Playing from cache: $videoPath');
          await _initializePlayer(videoPath);
          return;
        }
      }
      
      // Fallback: check if we have a local file path provided directly (without subtitle metadata)
      if (widget.localFilePath != null) {
        final file = File(widget.localFilePath!);
        if (await file.exists()) {
          debugPrint('Playing from local file without subtitles: ${widget.localFilePath}');
          await _initializePlayer(widget.localFilePath!);
          return;
        }
      }
      
      if (!mounted) return;
      
      // Fall back to streaming
      final provider = Provider.of<AnimeProvider>(context, listen: false);
      final data = await provider.getStreamingData(widget.episodeId, category: widget.category);

      if (_isDisposed) return;

      if (data == null || data.sources.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'No streaming sources available';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _streamingData = data;
          // Auto-select first English subtitle if available
          for (int i = 0; i < data.subtitles.length; i++) {
            if (data.subtitles[i].lang.toLowerCase().contains('english')) {
              _selectedSubtitleIndex = i;
              debugPrint('Auto-selected streaming subtitle: ${data.subtitles[i].lang}');
              break;
            }
          }
          if (_selectedSubtitleIndex < 0 && data.subtitles.isNotEmpty) {
            _selectedSubtitleIndex = 0; // Fallback to first subtitle
            debugPrint('Auto-selected first streaming subtitle: ${data.subtitles[0].lang}');
          }
        });
      }

      await _initializePlayer(data.sources[0].url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading video: $e';
        });
      }
    }
  }

  Future<void> _initializePlayer(String videoUrl) async {
    if (_isDisposed) return;
    
    try {
      debugPrint('Playing video URL: $videoUrl');
      
      // Listen for when video is actually ready
      StreamSubscription? durationListener;
      durationListener = _player.stream.duration.listen((duration) async {
        if (duration > Duration.zero && !_isDisposed) {
          debugPrint('Video ready! Duration: $duration');
          
          // Resume from saved position when video is ready
          if (_resumePosition != null && !_hasResumed) {
            _hasResumed = true;
            // Small delay to ensure player is fully ready for seeking
            await Future.delayed(const Duration(milliseconds: 300));
            if (!_isDisposed) {
              await _player.seek(_resumePosition!);
              debugPrint('Resumed playback at: ${_resumePosition!.inSeconds}s');
              
              // Show resume tooltip with progress bar
              if (mounted) {
                _showResumeTooltipWithProgress();
              }
            }
          }
          
          durationListener?.cancel();
        }
      });
      
      // Detect video resolution (logging only)
      _player.stream.width.listen((width) {
        if (width != null && width > 0) {
          debugPrint('Detected video width: $width');
        }
      });
      _player.stream.height.listen((height) {
        if (height != null && height > 0) {
          debugPrint('Detected video height: $height');
        }
      });
      
      // Open the media
      await _player.open(
        Media(
          videoUrl,
          httpHeaders: {
            'Referer': _streamingData?.referer ?? 'https://megacloud.blog/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      
      // Explicitly start playback
      await _player.play();
      await _player.setRate(_playbackSpeed);

      // Load subtitle if selected
      if (_selectedSubtitleIndex >= 0 && _streamingData != null && _streamingData!.subtitles.isNotEmpty) {
        debugPrint('Loading subtitle track $_selectedSubtitleIndex: ${_streamingData!.subtitles[_selectedSubtitleIndex].lang}');
        _loadSubtitle(_streamingData!.subtitles[_selectedSubtitleIndex]);
      } else {
        debugPrint('No subtitle to load. Index: $_selectedSubtitleIndex, hasData: ${_streamingData != null}, subtitles: ${_streamingData?.subtitles.length ?? 0}');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing player: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load video: $e';
        });
      }
    }
  }

  void _loadSubtitle(SubtitleInfo subtitle) {
    try {
      // Handle both remote URLs and local file paths
      String subtitleUri = subtitle.url;
      debugPrint('Raw subtitle URL: ${subtitle.url}');
      
      if (!subtitle.url.startsWith('http') && !subtitle.url.startsWith('file://')) {
        // Convert local file path to URI
        final file = File(subtitle.url);
        if (!file.existsSync()) {
          debugPrint('ERROR: Subtitle file does not exist: ${subtitle.url}');
          return;
        }
        subtitleUri = Uri.file(subtitle.url).toString();
        debugPrint('Converted to file URI: $subtitleUri');
      }
      
      debugPrint('Setting subtitle track: ${subtitle.lang} from $subtitleUri');
      _player.setSubtitleTrack(
        SubtitleTrack.uri(
          subtitleUri,
          title: subtitle.lang,
          language: subtitle.lang,
        ),
      );
      debugPrint('Successfully loaded subtitle: ${subtitle.lang}');
    } catch (e) {
      debugPrint('ERROR loading subtitle: $e');
      debugPrint('Subtitle details - URL: ${subtitle.url}, Lang: ${subtitle.lang}');
    }
  }

  void _disableSubtitles() {
    try {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } catch (e) {
      debugPrint('Error disabling subtitles: $e');
    }
  }

  Future<void> _changeSource(int index) async {
    if (_streamingData == null || index < 0 || index >= _streamingData!.sources.length) return;
    
    final currentPosition = _player.state.position;
    
    if (mounted) {
      setState(() {
        _isLoading = true;
        _selectedSourceIndex = index;
      });
    }
    
    await _initializePlayer(_streamingData!.sources[index].url);
    
    // Seek to previous position
    await Future.delayed(const Duration(milliseconds: 500));
    _player.seek(currentPosition);
  }

  void _changeSubtitle(int index) {
    setState(() {
      _selectedSubtitleIndex = index;
    });
    
    if (index < 0) {
      _disableSubtitles();
    } else if (_streamingData != null && index < _streamingData!.subtitles.length) {
      _loadSubtitle(_streamingData!.subtitles[index]);
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _player.setRate(speed);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _onUserInteraction(),
          child: GestureDetector(
            onTap: () {
              _focusNode.requestFocus(); // Ensure focus for keyboard
              setState(() {
                _showControls = !_showControls;
                if (_showControls) {
                  _showSettings = false;
                  _startHideControlsTimer();
                }
              });
            },
          child: Stack(
            children: [
              // Video Player
              Center(
                child: _buildVideoContent(),
              ),
              
              // Top Bar
              if (_showControls || _showSettings)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(),
                ),
              
              // Settings Panel (hide bottom controls when open)
              if (_showSettings)
                Positioned(
                  top: 60,
                  right: 16,
                  bottom: 16,
                  child: _buildSettingsPanel(),
                ),
              
              // Bottom Controls (hide when settings panel is open)
              if (_showControls && !_showSettings && !_isLoading && _errorMessage == null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomControls(),
                ),
              
              // Autoplay Next Episode Overlay
              if (_showAutoplayOverlay && _nextEpisode != null)
                _buildAutoplayOverlay(),
                
              // Resume Tooltip (top left)
              if (_showResumeTooltip && _resumePosition != null)
                _buildResumeTooltip(),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildTopBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.episodeTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            CategoryChip(
                              label: widget.category.toUpperCase(),
                              isSub: widget.category == 'sub',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: _showSettings ? AppColors.neonYellow.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.settings,
                        color: _showSettings ? AppColors.neonYellow : AppColors.textPrimary,
                      ),
                      onPressed: () {
                        setState(() {
                          _showSettings = !_showSettings;
                          if (_showSettings) {
                            _hideControlsTimer?.cancel();
                          } else {
                            _startHideControlsTimer();
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sources Section
                _buildSettingsSection(
              'Video Source',
              Icons.video_library,
              _streamingData?.sources.asMap().entries.map((entry) {
                final source = entry.value;
                return _buildSettingsOption(
                  source.quality,
                  entry.key == _selectedSourceIndex,
                  () => _changeSource(entry.key),
                  subtitle: source.isM3U8 ? 'HLS' : 'Direct',
                );
              }).toList() ?? [],
            ),
            
            Divider(color: AppColors.glassBorder),
            
            // Subtitles Section
            _buildSettingsSection(
              'Subtitles',
              Icons.subtitles,
              [
                _buildSettingsOption(
                  'Off',
                  _selectedSubtitleIndex == -1,
                  () => _changeSubtitle(-1),
                ),
                ...(_streamingData?.subtitles.asMap().entries.map((entry) {
                  return _buildSettingsOption(
                    entry.value.lang,
                    entry.key == _selectedSubtitleIndex,
                    () => _changeSubtitle(entry.key),
                  );
                }).toList() ?? []),
              ],
            ),
            
            Divider(color: AppColors.glassBorder),
            
            // Playback Speed Section
            _buildSettingsSection(
              'Playback Speed',
              Icons.speed,
              _speedOptions.map((speed) {
                return _buildSettingsOption(
                  '${speed}x',
                  _playbackSpeed == speed,
                  () => _changePlaybackSpeed(speed),
                );
              }).toList(),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(String title, IconData icon, List<Widget> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.neonYellow, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        ...options,
      ],
    );
  }

  Widget _buildSettingsOption(String label, bool isSelected, VoidCallback onTap, {String? subtitle}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.neonYellow.withValues(alpha: 0.15) : Colors.transparent,
          border: isSelected ? Border(left: BorderSide(color: AppColors.neonYellow, width: 3)) : null,
        ),
        child: Row(
          children: [
            if (isSelected)
              Icon(Icons.check, color: AppColors.neonYellow, size: 18)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? AppColors.neonYellow : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isTvMode = TvInputDetector.instance.isLikelyTv || Platform.isAndroid;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.4),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek Mode Indicator
              if (_isSeekMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neonYellow.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fast_rewind, color: AppColors.neonYellow, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'SEEK MODE  •  ◀▶ to seek  •  OK to exit',
                        style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.fast_forward, color: AppColors.neonYellow, size: 16),
                    ],
                  ),
                ),
              
              // Progress bar with enhanced styling for TV
              StreamBuilder<Duration>(
                stream: _player.stream.position,
                initialData: _player.state.position,
                builder: (context, positionSnapshot) {
                  return StreamBuilder<Duration>(
                    stream: _player.stream.duration,
                    initialData: _player.state.duration,
                    builder: (context, durationSnapshot) {
                      final position = positionSnapshot.data ?? _player.state.position;
                      final duration = durationSnapshot.data ?? _player.state.duration;
                      
                      return Column(
                        children: [
                          // Enhanced slider with seek mode highlight
                          Container(
                            decoration: _isSeekMode ? BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.5), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonYellow.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                ),
                              ],
                            ) : null,
                            padding: _isSeekMode ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : EdgeInsets.zero,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: _isSeekMode ? 10 : 6),
                                overlayShape: RoundSliderOverlayShape(overlayRadius: _isSeekMode ? 18 : 12),
                                trackHeight: _isSeekMode ? 6 : 3,
                              ),
                              child: Slider(
                                value: duration.inMilliseconds > 0 
                                    ? position.inMilliseconds / duration.inMilliseconds 
                                    : 0,
                                onChanged: (value) {
                                  _onUserInteraction();
                                  final newPosition = Duration(
                                    milliseconds: (value * duration.inMilliseconds).round(),
                                  );
                                  _player.seek(newPosition);
                                },
                                activeColor: AppColors.neonYellow,
                                inactiveColor: AppColors.textMuted,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                                ),
                                // Remaining time
                                Text(
                                  '-${_formatDuration(duration - position)}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              
              const SizedBox(height: 8),
              
              // Control buttons with focus indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind 10s
                  _buildControlButton(
                    index: 0,
                    icon: Icons.replay_10,
                    size: 32,
                    onPressed: () {
                      _onUserInteraction();
                      final newPosition = _player.state.position - const Duration(seconds: 10);
                      _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
                    },
                  ),
                  const SizedBox(width: 16),
                  
                  // Play/Pause
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    initialData: _player.state.playing,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? _player.state.playing;
                      return _buildControlButton(
                        index: 1,
                        icon: isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 64,
                        isHighlighted: true,
                        onPressed: () {
                          _onUserInteraction();
                          _player.playOrPause();
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  
                  // Forward 10s
                  _buildControlButton(
                    index: 2,
                    icon: Icons.forward_10,
                    size: 32,
                    onPressed: () {
                      _onUserInteraction();
                      final newPosition = _player.state.position + const Duration(seconds: 10);
                      _player.seek(newPosition);
                    },
                  ),
                  
                  const Spacer(),
                  
                  // Settings button
                  _buildControlButton(
                    index: 3,
                    icon: Icons.settings,
                    size: 28,
                    onPressed: () {
                      setState(() => _showSettings = !_showSettings);
                      _onUserInteraction();
                    },
                  ),
                  const SizedBox(width: 8),
                  
                  // Fullscreen toggle
                  if (Platform.isWindows)
                    _buildControlButton(
                      index: 4,
                      icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      size: 28,
                      onPressed: _toggleFullscreen,
                    ),
                ],
              ),
              
              // TV Controls hint
              if (isTvMode)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isSeekMode 
                          ? '◀ -10s  │  ▶ +10s  │  ▲ Exit Seek  │  OK Confirm'
                          : '◀▶ Navigate  │  ▼ Seek Mode  │  ▲ Vol+  │  OK Select  │  ◀◀ Back',
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.9),
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build a control button with D-Pad focus indicator
  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
    bool isHighlighted = false,
  }) {
    final isFocused = _focusedControlIndex == index && !_isSeekMode;
    final isTvMode = TvInputDetector.instance.isLikelyTv || Platform.isAndroid;
    
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(isFocused && isTvMode ? 4 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isFocused && isTvMode 
              ? Border.all(color: AppColors.neonYellow, width: 3)
              : null,
          boxShadow: [
            if (isHighlighted || (isFocused && isTvMode))
              BoxShadow(
                color: AppColors.neonYellow.withValues(alpha: isFocused ? 0.6 : 0.4),
                blurRadius: isFocused ? 25 : 20,
              ),
          ],
        ),
        child: Icon(
          icon,
          color: isHighlighted ? AppColors.neonYellow : (isFocused ? AppColors.neonYellow : AppColors.textPrimary),
          size: size,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Show the resume tooltip with animated progress bar
  void _showResumeTooltipWithProgress() {
    _resumeTooltipTimer?.cancel();
    
    setState(() {
      _showResumeTooltip = true;
      _resumeTooltipProgress = 0.0;
    });
    
    // Animate the progress bar over 3 seconds
    const totalDuration = 3000; // 3 seconds
    const updateInterval = 50; // Update every 50ms
    int elapsed = 0;
    
    _resumeTooltipTimer = Timer.periodic(const Duration(milliseconds: updateInterval), (timer) {
      elapsed += updateInterval;
      
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (elapsed >= totalDuration) {
        timer.cancel();
        setState(() {
          _showResumeTooltip = false;
          _resumeTooltipProgress = 1.0;
        });
      } else {
        setState(() {
          _resumeTooltipProgress = elapsed / totalDuration;
        });
      }
    });
  }
  
  /// Build the resume tooltip widget
  Widget _buildResumeTooltip() {
    return Positioned(
      top: 80,
      left: 20,
      child: AnimatedOpacity(
        opacity: _showResumeTooltip ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.2),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          color: AppColors.neonYellow,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Resumed at ${_formatDuration(_resumePosition!)}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress bar that fills as tooltip is about to disappear
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(11),
                      bottomRight: Radius.circular(11),
                    ),
                    child: LinearProgressIndicator(
                      value: _resumeTooltipProgress,
                      backgroundColor: AppColors.surface,
                      valueColor: const AlwaysStoppedAnimation(AppColors.neonYellow),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the autoplay next episode overlay
  Widget _buildAutoplayOverlay() {
    // Use smaller, less intrusive overlay on mobile
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final overlayWidth = isMobile ? 200.0 : 340.0;
    final overlayPadding = isMobile ? 12.0 : 18.0;
    final iconSize = isMobile ? 20.0 : 26.0;
    final titleSize = isMobile ? 13.0 : 16.0;
    final episodeSize = isMobile ? 14.0 : 18.0;
    final countdownSize = isMobile ? 32.0 : 40.0;
    
    return Positioned(
      bottom: isMobile ? 80 : 100,
      right: isMobile ? 12 : 20,
      child: AnimatedOpacity(
        opacity: _showAutoplayOverlay ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: overlayWidth,
              padding: EdgeInsets.all(overlayPadding),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.2),
                    blurRadius: isMobile ? 15 : 25,
                    spreadRadius: isMobile ? 2 : 5,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.skip_next, color: AppColors.neonYellow, size: iconSize),
                  SizedBox(width: isMobile ? 6 : 10),
                  Expanded(
                    child: NeonText(
                      'Up Next',
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Countdown circle
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: countdownSize,
                        height: countdownSize,
                        child: CircularProgressIndicator(
                          value: _autoplayCountdown / 15, // 15 second countdown
                          backgroundColor: AppColors.surface,
                          valueColor: const AlwaysStoppedAnimation(AppColors.neonYellow),
                          strokeWidth: isMobile ? 2 : 3,
                        ),
                      ),
                      Text(
                        '$_autoplayCountdown',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: isMobile ? 10 : 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 8 : 14),
              
              // Episode info
              Text(
                'Episode ${_nextEpisode!.number}',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: episodeSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_nextEpisode!.title != null && !isMobile) ...[
                const SizedBox(height: 6),
                Text(
                  _nextEpisode!.title!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!isMobile) ...[
                const SizedBox(height: 8),
                CategoryChip(
                  label: widget.category.toUpperCase(),
                  isSub: widget.category == 'sub',
                ),
              ],
              SizedBox(height: isMobile ? 10 : 18),
              
              // Buttons - compact on mobile
              if (isMobile)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancelAutoplay,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(color: AppColors.glassBorder),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text('✕', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _playNextEpisode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonYellow,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text('Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                )
              else
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelAutoplay,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.glassBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Play now button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _playNextEpisode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonYellow,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Play Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.neonYellow),
          const SizedBox(height: 16),
          const Text(
            'Loading video...',
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 64),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadStreamingData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonYellow,
              foregroundColor: AppColors.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }

    return Video(
      controller: _controller,
      controls: NoVideoControls,
    );
  }
}
/// Download dialog for autoplay next episode
class _AutoplayDownloadDialog extends StatefulWidget {
  final String animeTitle;
  final int episodeNumber;
  final String category;
  final Future<CachedEpisode?> Function(
    void Function(double progress, String status) onProgress,
  ) onDownload;

  const _AutoplayDownloadDialog({
    required this.animeTitle,
    required this.episodeNumber,
    required this.category,
    required this.onDownload,
  });

  @override
  State<_AutoplayDownloadDialog> createState() => _AutoplayDownloadDialogState();
}

class _AutoplayDownloadDialogState extends State<_AutoplayDownloadDialog> {
  double _progress = 0.0;
  String _status = 'Preparing...';
  bool _isComplete = false;
  String? _error;
  int _retryCount = 0;
  // No max retries - keep trying until user cancels or it succeeds

  @override
  void initState() {
    super.initState();
    // Small delay before starting to let system resources settle
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startDownload();
    });
  }

  Future<void> _startDownload() async {
    if (!mounted) return;
    
    setState(() {
      _error = null;
      _progress = 0.0;
      if (_retryCount == 0) {
        _status = 'Fetching stream...';
      } else if (_retryCount < 3) {
        _status = 'Connecting to server...';
      } else {
        _status = 'Please wait, server is busy...';
      }
    });
    
    try {
      final result = await widget.onDownload((progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _status = status;
          });
        }
      });

      if (mounted) {
        if (result != null) {
          setState(() {
            _isComplete = true;
            _progress = 1.0;
          });
          // Auto close and return result
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pop(result);
          }
        } else {
          // Download returned null - keep retrying (service handles its own retries)
          _retryCount++;
          debugPrint('Download returned null, auto-retrying (attempt ${_retryCount + 1})');
          // Short delay before retrying the whole flow
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) _startDownload();
        }
      }
    } catch (e) {
      if (mounted) {
        // Keep retrying on exception
        _retryCount++;
        debugPrint('Download exception, auto-retrying (attempt ${_retryCount + 1}): $e');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _startDownload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.skip_next, color: AppColors.neonYellow, size: 28),
                    const SizedBox(width: 10),
                    const NeonText(
                      'Up Next',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                
                // Episode info
                Text(
                  '${widget.animeTitle} - Episode ${widget.episodeNumber}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                CategoryChip(
                  label: widget.category.toUpperCase(),
                  isSub: widget.category == 'sub',
                ),
                const SizedBox(height: 22),
                
                // Icon with glow
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _error != null 
                          ? [AppColors.error, AppColors.error.withValues(alpha: 0.7)]
                          : _isComplete 
                              ? [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.7)]
                              : [AppColors.neonYellow.withValues(alpha: 0.3), AppColors.neonYellow.withValues(alpha: 0.1)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_error != null ? AppColors.error : AppColors.neonYellow).withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(
                    _error != null 
                        ? Icons.error_outline
                        : _isComplete 
                            ? Icons.check
                            : Icons.cloud_download,
                    color: _error != null || _isComplete 
                        ? AppColors.background 
                        : AppColors.neonYellow,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                
                // Message
                Text(
                  _error != null
                      ? 'Oops! Something went wrong'
                      : _isComplete
                          ? 'Ready to play!'
                          : 'Caching next episode for smooth playback...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                
                // Progress bar (always shown while downloading)
                if (!_isComplete) ...[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonYellow.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null, // Indeterminate when fetching
                        backgroundColor: AppColors.surface,
                        valueColor: const AlwaysStoppedAnimation(AppColors.neonYellow),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (_progress > 0) ...[
                    const SizedBox(height: 6),
                    NeonText(
                      '${(_progress * 100).toInt()}%',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ],
                  const SizedBox(height: 18),
                  // Cancel button always available
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}