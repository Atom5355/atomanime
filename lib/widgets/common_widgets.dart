import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/download_cache_service.dart';
import '../theme/app_theme.dart';

class LoadingIndicator extends StatelessWidget {
  final String? message;

  const LoadingIndicator({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.neonYellow),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorDisplay({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonYellow,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.neonYellow.withValues(alpha: 0.5), size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable caching progress dialog for downloading episodes
class CachingProgressDialog extends StatefulWidget {
  final String animeTitle;
  final int episodeNumber;
  final Future<CachedEpisode?> Function(
    void Function(double progress, String status) onProgress,
  ) onDownload;

  const CachingProgressDialog({
    super.key,
    required this.animeTitle,
    required this.episodeNumber,
    required this.onDownload,
  });

  @override
  State<CachingProgressDialog> createState() => _CachingProgressDialogState();
  
  /// Helper method to show the dialog and cache an episode
  /// Returns the cached episode if successful, null otherwise
  static Future<CachedEpisode?> showAndCache({
    required BuildContext context,
    required String animeId,
    required String animeTitle,
    required String episodeId,
    required int episodeNumber,
    required String category,
    String? coverImage,
  }) async {
    final cacheService = DownloadCacheService();
    CachedEpisode? result;
    
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CachingProgressDialog(
        animeTitle: animeTitle,
        episodeNumber: episodeNumber,
        onDownload: (onProgress) async {
          result = await cacheService.downloadEpisode(
            animeId: animeId,
            animeTitle: animeTitle,
            episodeId: episodeId,
            episodeNumber: episodeNumber,
            category: category,
            coverImage: coverImage,
            onProgress: onProgress,
          );
          return result;
        },
      ),
    );
    
    return success == true ? result : null;
  }
}

class _CachingProgressDialogState extends State<CachingProgressDialog> {
  double _progress = 0.0;
  String _status = 'Starting...';
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
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
          // Auto close after brief success display
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } else {
          setState(() {
            _error = 'Download failed';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
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
            width: 340,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 20),
                
                // Message
                Text(
                  _error != null
                      ? 'Oops! Something went wrong'
                      : _isComplete
                          ? 'Ready to play!'
                          : 'Let us cache this episode so you don\'t buffer!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Episode info
                Text(
                  'Episode ${widget.episodeNumber}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Progress bar (only when downloading)
                if (_error == null && !_isComplete) ...[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonYellow.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null, // Indeterminate if 0
                        backgroundColor: AppColors.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonYellow),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  NeonText(
                    _progress > 0 
                        ? '${(_progress * 100).toStringAsFixed(0)}%'
                        : 'Connecting...',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  // Show speed if available
                  if (_status.contains('•')) ...[
                    const SizedBox(height: 6),
                    Text(
                      _status.split('•').last.trim(),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
                
                // Error message
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.error.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Close'),
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
