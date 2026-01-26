import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/profile_service.dart';
import '../services/download_cache_service.dart';
import '../models/profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'video_player_screen.dart';

/// Screen showing watch history grouped by anime
class WatchHistoryScreen extends StatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen> {
  final ProfileService _profileService = ProfileService();
  final DownloadCacheService _cacheService = DownloadCacheService();
  
  List<WatchHistory> _allHistory = [];
  Set<String> _cachedEpisodes = {}; // Track which episodes are cached
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    try {
      final allHistory = await _profileService.getWatchHistory(limit: 200);
      
      // Check cache status for each item
      final cached = <String>{};
      for (final history in allHistory) {
        final cachedEpisode = await _cacheService.getCachedEpisode(
          history.animeId,
          history.animeTitle,
          history.episodeNumber,
          history.category,
        );
        if (cachedEpisode != null) {
          cached.add('${history.animeId}_${history.episodeNumber}_${history.category}');
        }
      }
      
      if (mounted) {
        setState(() {
          _allHistory = allHistory;
          _cachedEpisodes = cached;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading watch history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  /// Play episode - ensures it's cached first (desktop only)
  Future<void> _playEpisode(WatchHistory history) async {
    // On mobile platforms, skip caching and stream directly (HLS streams can't be downloaded via HTTP)
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    String? localFilePath;
    
    if (!isMobile) {
      final cacheService = DownloadCacheService();
      
      // Check if episode is already cached
      final cached = await cacheService.getCachedEpisode(
        history.animeId,
        history.animeTitle,
        history.episodeNumber,
        history.category,
      );
      
      localFilePath = cached?.filePath;
      
      // If not cached, download first (desktop only)
      if (localFilePath == null) {
        if (!mounted) return;
        
        final result = await CachingProgressDialog.showAndCache(
          context: context,
          animeId: history.animeId,
          animeTitle: history.animeTitle,
          episodeId: history.episodeId,
          episodeNumber: history.episodeNumber,
          category: history.category,
          coverImage: history.coverImage,
        );
        
        if (result == null || !mounted) return;
        localFilePath = result.filePath;
      }
    }
    
    if (!mounted) return;
    
    // Navigate to video player with cached file
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          episodeId: history.episodeId,
          episodeTitle: 'Episode ${history.episodeNumber}',
          category: history.category,
          episodeNumber: history.episodeNumber,
          animeId: history.animeId,
          animeTitle: history.animeTitle,
          coverImage: history.coverImage,
          localFilePath: localFilePath,
        ),
      ),
    ).then((_) => _loadHistory());
  }

  Future<void> _clearAnimeHistory(WatchHistory history) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.delete_forever, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Clear History',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Clear all watch history for "${history.animeTitle}"?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Clear'),
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

    if (confirm == true) {
      await _profileService.clearAnimeHistory(history.animeId);
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profileService.currentProfile;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: AppColors.glass),
          ),
        ),
        leading: GlassCard(
          margin: const EdgeInsets.all(8),
          padding: EdgeInsets.zero,
          borderRadius: 10,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const NeonText('Watch History', fontSize: 18, fontWeight: FontWeight.bold),
        actions: [
          if (profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(int.parse((profile.avatarColor ?? '#673AB7').replaceFirst('#', '0xFF'))).withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(int.parse((profile.avatarColor ?? '#673AB7').replaceFirst('#', '0xFF'))),
                  child: Text(
                    profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.neonYellow))
                : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_allHistory.isEmpty) {
      return Center(
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64, color: AppColors.neonYellow.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text(
                'No watch history',
                style: TextStyle(fontSize: 18, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start watching something!',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    // Group by anime
    final grouped = <String, List<WatchHistory>>{};
    for (final history in _allHistory) {
      grouped.putIfAbsent(history.animeId, () => []).add(history);
    }

    // Sort each anime's episodes by most recent
    for (final episodes in grouped.values) {
      episodes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    // Sort anime groups by most recently watched
    final sortedAnimeIds = grouped.keys.toList()
      ..sort((a, b) => grouped[b]!.first.updatedAt.compareTo(grouped[a]!.first.updatedAt));

    return RefreshIndicator(
      color: AppColors.neonYellow,
      backgroundColor: AppColors.surface,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedAnimeIds.length,
        itemBuilder: (context, index) {
          final animeId = sortedAnimeIds[index];
          final episodes = grouped[animeId]!;
          return _buildAnimeCard(episodes);
        },
      ),
    );
  }

  Widget _buildAnimeCard(List<WatchHistory> episodes) {
    // Episodes are already sorted by updatedAt (most recent first)
    // So firstEpisode is the most recently watched episode
    final mostRecentEpisode = episodes.first;
    final completedCount = episodes.where((e) => e.completed).length;
    final inProgressCount = episodes.where((e) => !e.completed && e.watchedDuration.inSeconds > 30).length;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Main anime header with cover image
          InkWell(
            onTap: () => _playEpisode(mostRecentEpisode),
            onLongPress: () => _clearAnimeHistory(mostRecentEpisode),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Anime cover image with glow
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonYellow.withValues(alpha: 0.2),
                            blurRadius: 15,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                        child: SizedBox(
                          width: 105,
                          height: 150,
                          child: _buildCoverImage(mostRecentEpisode.coverImage),
                        ),
                      ),
                    ),
                    // Play overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.neonYellow.withValues(alpha: 0.9),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonYellow.withValues(alpha: 0.5),
                                  blurRadius: 15,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.play_arrow, color: AppColors.background, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mostRecentEpisode.animeTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        // Stats row
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildStatChip(
                              Icons.movie,
                              '${episodes.length} ep${episodes.length > 1 ? 's' : ''}',
                              AppColors.neonYellow,
                            ),
                            if (completedCount > 0)
                              _buildStatChip(
                                Icons.check_circle,
                                '$completedCount done',
                                AppColors.neonYellow,
                              ),
                            if (inProgressCount > 0)
                              _buildStatChip(
                                Icons.play_arrow,
                                '$inProgressCount in progress',
                                AppColors.neonYellow.withValues(alpha: 0.7),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Continue info - show which episode will play
                        if (!mostRecentEpisode.completed) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.neonYellow.withValues(alpha: 0.2), AppColors.neonYellow.withValues(alpha: 0.1)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'Continue EP ${mostRecentEpisode.episodeNumber} • ${_formatDuration(mostRecentEpisode.watchedDuration)}',
                              style: TextStyle(
                                color: AppColors.neonYellow,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.neonYellow.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Last: EP ${mostRecentEpisode.episodeNumber} ✓',
                              style: TextStyle(
                                color: AppColors.neonYellow,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          _formatTimeAgo(mostRecentEpisode.updatedAt),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline, color: AppColors.error.withValues(alpha: 0.8), size: 22),
                  onPressed: () => _clearAnimeHistory(mostRecentEpisode),
                ),
              ],
            ),
          ),
          // Expandable episode list
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'View all ${episodes.length} episode${episodes.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              leading: Icon(Icons.list, size: 18, color: AppColors.neonYellow.withValues(alpha: 0.7)),
              iconColor: AppColors.neonYellow,
              collapsedIconColor: AppColors.textMuted,
              children: episodes.map((ep) => _buildEpisodeTile(ep)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeTile(WatchHistory history) {
    final progress = history.progress;
    final resumeTime = _formatDuration(history.watchedDuration);
    final totalTime = _formatDuration(history.totalDuration);
    final cacheKey = '${history.animeId}_${history.episodeNumber}_${history.category}';
    final isCached = _cachedEpisodes.contains(cacheKey);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ListTile(
        onTap: () => _playEpisode(history),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: progress,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation(
                  history.completed ? AppColors.neonYellow : AppColors.neonYellow.withValues(alpha: 0.6),
                ),
                strokeWidth: 3,
              ),
            ),
            Text(
              '${history.episodeNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary),
            ),
          ],
        ),
        title: Text(
          'Episode ${history.episodeNumber}',
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        ),
        subtitle: Row(
          children: [
            Text(
              history.completed 
                  ? 'Completed • $totalTime'
                  : '$resumeTime / $totalTime',
              style: TextStyle(
                color: history.completed ? AppColors.neonYellow : AppColors.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            // Cached indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isCached 
                    ? AppColors.neonYellow.withValues(alpha: 0.15)
                    : AppColors.glass,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCached ? Icons.download_done : Icons.cloud_download,
                    size: 10,
                    color: isCached ? AppColors.neonYellow : AppColors.textMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isCached ? 'Cached' : 'Stream',
                    style: TextStyle(
                      fontSize: 9,
                      color: isCached ? AppColors.neonYellow : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryChip(
              label: history.category.toUpperCase(),
              isSub: history.category == 'sub',
            ),
            const SizedBox(width: 8),
            Icon(
              history.completed ? Icons.check_circle : Icons.play_circle_outline,
              color: history.completed ? AppColors.neonYellow : AppColors.textPrimary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(String? coverImage) {
    if (coverImage != null) {
      return CachedNetworkImage(
        imageUrl: coverImage,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppColors.surface,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonYellow)),
        ),
        errorWidget: (context, url, error) => Container(
          color: AppColors.surface,
          child: const Icon(Icons.movie, color: AppColors.textMuted),
        ),
      );
    }
    return Container(
      color: AppColors.surface,
      child: const Icon(Icons.movie, color: AppColors.textMuted, size: 40),
    );
  }
}
