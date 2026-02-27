import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/profile_service.dart';
import '../services/download_cache_service.dart';
import '../models/profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/focusable_widget.dart';
import 'video_player_screen.dart';

/// Watch History screen - fully accessible on PC, Android, and TV (D-Pad)
class WatchHistoryScreen extends StatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen> {
  final ProfileService _profileService = ProfileService();
  final DownloadCacheService _cacheService = DownloadCacheService();
  
  List<WatchHistory> _allHistory = [];
  Set<String> _cachedEpisodes = {};
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
      
      final cached = <String>{};
      for (final history in allHistory) {
        final cachedEpisode = await _cacheService.getCachedEpisode(
          history.animeId, history.animeTitle, history.episodeNumber, history.category,
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 30) return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    if (difference.inDays > 0) return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    if (difference.inHours > 0) return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    return 'Just now';
  }

  Future<void> _playEpisode(WatchHistory history) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    String? localFilePath;
    
    if (!isMobile) {
      final cached = await _cacheService.getCachedEpisode(
        history.animeId, history.animeTitle, history.episodeNumber, history.category,
      );
      localFilePath = cached?.filePath;
      
      if (localFilePath == null) {
        if (!mounted) return;
        final result = await CachingProgressDialog.showAndCache(
          context: context, animeId: history.animeId, animeTitle: history.animeTitle,
          episodeId: history.episodeId, episodeNumber: history.episodeNumber,
          category: history.category, coverImage: history.coverImage,
        );
        if (result == null || !mounted) return;
        localFilePath = result.filePath;
      }
    }
    
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => VideoPlayerScreen(
        episodeId: history.episodeId, episodeTitle: 'Episode ${history.episodeNumber}',
        category: history.category, episodeNumber: history.episodeNumber,
        animeId: history.animeId, animeTitle: history.animeTitle,
        coverImage: history.coverImage, localFilePath: localFilePath,
      ),
    )).then((_) => _loadHistory());
  }

  Future<void> _clearAnimeHistory(WatchHistory history) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.glassBorder)),
        title: const Text('Clear History', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Clear all watch history for "${history.animeTitle}"?', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          UniversalButton(label: 'Cancel', isPrimary: false, onPressed: () => Navigator.pop(context, false)),
          UniversalButton(label: 'Clear', color: AppColors.error, textColor: Colors.white, onPressed: () => Navigator.pop(context, true)),
        ],
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
        leading: FocusableWidget(
          onSelect: () => Navigator.pop(context),
          builder: (context, isFocused, isHovered) {
            return Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isFocused ? AppColors.neonYellow : AppColors.glass,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isFocused ? AppColors.neonYellow : AppColors.glassBorder),
              ),
              child: Icon(Icons.arrow_back, color: isFocused ? AppColors.background : AppColors.textPrimary),
            );
          },
        ),
        title: const NeonText('Watch History', fontSize: 18, fontWeight: FontWeight.bold),
        actions: [
          if (profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Color(int.parse((profile.avatarColor ?? '#673AB7').replaceFirst('#', '0xFF'))),
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
              const Text('No watch history', style: TextStyle(fontSize: 18, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Start watching something!', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
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
    for (final episodes in grouped.values) {
      episodes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
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
          return _buildAnimeCard(grouped[animeId]!);
        },
      ),
    );
  }

  Widget _buildAnimeCard(List<WatchHistory> episodes) {
    final mostRecentEpisode = episodes.first;
    final completedCount = episodes.where((e) => e.completed).length;
    final inProgressCount = episodes.where((e) => !e.completed && e.watchedDuration.inSeconds > 30).length;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Main anime header - focusable for play
          FocusableWidget(
            onSelect: () => _playEpisode(mostRecentEpisode),
            onLongPress: () => _clearAnimeHistory(mostRecentEpisode),
            builder: (context, isFocused, isHovered) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: isFocused ? Border.all(color: AppColors.neonYellow, width: 2) : null,
                  boxShadow: isFocused ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.3), blurRadius: 12)] : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Anime cover
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                            boxShadow: [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.2), blurRadius: 15)],
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                            child: SizedBox(width: 105, height: 150, child: _buildCoverImage(mostRecentEpisode.coverImage)),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16))),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFocused ? AppColors.neonYellow : AppColors.neonYellow.withValues(alpha: 0.9),
                                  boxShadow: [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.5), blurRadius: 15)],
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
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isFocused ? AppColors.neonYellow : AppColors.textPrimary),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              _buildStatChip(Icons.movie, '${episodes.length} ep${episodes.length > 1 ? 's' : ''}', AppColors.neonYellow),
                              if (completedCount > 0) _buildStatChip(Icons.check_circle, '$completedCount done', AppColors.neonYellow),
                              if (inProgressCount > 0) _buildStatChip(Icons.play_arrow, '$inProgressCount in progress', AppColors.neonYellow.withValues(alpha: 0.7)),
                            ]),
                            const SizedBox(height: 10),
                            if (!mostRecentEpisode.completed) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [AppColors.neonYellow.withValues(alpha: 0.2), AppColors.neonYellow.withValues(alpha: 0.1)]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
                                ),
                                child: Text('Continue EP ${mostRecentEpisode.episodeNumber} • ${_formatDuration(mostRecentEpisode.watchedDuration)}',
                                  style: TextStyle(color: AppColors.neonYellow, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppColors.neonYellow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text('Last: EP ${mostRecentEpisode.episodeNumber} ✓',
                                  style: TextStyle(color: AppColors.neonYellow, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(_formatTimeAgo(mostRecentEpisode.updatedAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    // Delete button - focusable
                    Padding(
                      padding: const EdgeInsets.only(top: 14, right: 8),
                      child: FocusableWidget(
                        onSelect: () => _clearAnimeHistory(mostRecentEpisode),
                        builder: (context, isFocused, isHovered) {
                          return Icon(Icons.delete_outline, color: isFocused ? AppColors.error : AppColors.error.withValues(alpha: 0.8), size: 22);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Expandable episode list
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('View all ${episodes.length} episode${episodes.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildEpisodeTile(WatchHistory history) {
    final progress = history.progress;
    final resumeTime = _formatDuration(history.watchedDuration);
    final totalTime = _formatDuration(history.totalDuration);
    final cacheKey = '${history.animeId}_${history.episodeNumber}_${history.category}';
    final isCached = _cachedEpisodes.contains(cacheKey);
    
    return FocusableWidget(
      onSelect: () => _playEpisode(history),
      builder: (context, isFocused, isHovered) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isFocused ? AppColors.surface : AppColors.glass,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isFocused ? AppColors.neonYellow : AppColors.glassBorder, width: isFocused ? 2 : 1),
            boxShadow: isFocused ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.3), blurRadius: 10)] : null,
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    value: progress, backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation(history.completed ? AppColors.neonYellow : AppColors.neonYellow.withValues(alpha: 0.6)),
                    strokeWidth: 3,
                  ),
                ),
                Text('${history.episodeNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary)),
              ],
            ),
            title: Text('Episode ${history.episodeNumber}',
              style: TextStyle(fontSize: 13, color: isFocused ? AppColors.neonYellow : AppColors.textPrimary)),
            subtitle: Row(
              children: [
                Text(
                  history.completed ? 'Completed • $totalTime' : '$resumeTime / $totalTime',
                  style: TextStyle(color: history.completed ? AppColors.neonYellow : AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCached ? AppColors.neonYellow.withValues(alpha: 0.15) : AppColors.glass,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isCached ? Icons.download_done : Icons.cloud_download, size: 10, color: isCached ? AppColors.neonYellow : AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text(isCached ? 'Cached' : 'Stream', style: TextStyle(fontSize: 9, color: isCached ? AppColors.neonYellow : AppColors.textMuted)),
                  ]),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryChip(label: history.category.toUpperCase(), isSub: history.category == 'sub'),
                const SizedBox(width: 8),
                Icon(
                  history.completed ? Icons.check_circle : Icons.play_circle_outline,
                  color: isFocused ? AppColors.neonYellow : (history.completed ? AppColors.neonYellow : AppColors.textPrimary),
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverImage(String? coverImage) {
    if (coverImage != null) {
      return CachedNetworkImage(
        imageUrl: coverImage, fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: AppColors.surface, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonYellow))),
        errorWidget: (context, url, error) => Container(color: AppColors.surface, child: const Icon(Icons.movie, color: AppColors.textMuted)),
      );
    }
    return Container(color: AppColors.surface, child: const Icon(Icons.movie, color: AppColors.textMuted, size: 40));
  }
}
