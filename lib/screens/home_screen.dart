import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/anime_provider.dart';
import '../models/anime.dart';
import '../services/profile_service.dart';
import '../services/download_cache_service.dart';
import '../services/aniwatch_service.dart';
import '../models/profile.dart';
import '../widgets/common_widgets.dart';
import '../widgets/focusable_widget.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;
import 'anime_details_screen.dart';
import 'downloads_screen.dart';
import 'search_screen.dart';
import 'watch_history_screen.dart';
import 'video_player_screen.dart';

/// Wrapper for continue watching items with "next episode" recommendation
class ContinueWatchingItem {
  final WatchHistory history;
  final bool isNextEpisode;
  final int displayEpisodeNumber;
  final String? nextEpisodeId;
  
  ContinueWatchingItem({
    required this.history,
    this.isNextEpisode = false,
    int? displayEpisode,
    this.nextEpisodeId,
  }) : displayEpisodeNumber = displayEpisode ?? history.episodeNumber;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Continue Watching
  final ProfileService _profileService = ProfileService();
  final DownloadCacheService _cacheService = DownloadCacheService();
  final AniwatchService _aniwatchService = AniwatchService();
  List<ContinueWatchingItem> _continueWatching = [];
  Set<String> _cachedEpisodes = {};
  bool _isLoadingContinueWatching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnimeProvider>(context, listen: false).loadHomePage();
      _loadContinueWatching();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadContinueWatching();
    }
  }
  
  Future<void> _loadContinueWatching() async {
    if (_isLoadingContinueWatching) return;
    
    setState(() => _isLoadingContinueWatching = true);
    
    try {
      final results = await _profileService.getContinueWatching(limit: 50);
      
      final grouped = <String, WatchHistory>{};
      for (final history in results) {
        final key = '${history.animeId}_${history.category}';
        if (!grouped.containsKey(key) || 
            history.updatedAt.isAfter(grouped[key]!.updatedAt)) {
          grouped[key] = history;
        }
      }
      
      final groupedList = grouped.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      
      final continueWatchingItems = <ContinueWatchingItem>[];
      
      for (final history in groupedList) {
        // Use percentage-based check (~96% complete) instead of time-based
        final progress = history.totalDuration > Duration.zero
            ? history.watchedDuration.inSeconds / history.totalDuration.inSeconds
            : 0.0;
        final isNearEnd = progress >= 0.96 && history.totalDuration > Duration.zero;
        
        if (isNearEnd) {
          try {
            final episodes = await _aniwatchService.getEpisodes(history.animeId);
            final nextEpNumber = history.episodeNumber + 1;
            final nextEpisode = episodes.where((e) => e.number == nextEpNumber).firstOrNull;
            
            if (nextEpisode != null) {
              continueWatchingItems.add(ContinueWatchingItem(
                history: history,
                isNextEpisode: true,
                displayEpisode: nextEpNumber,
                nextEpisodeId: nextEpisode.id,
              ));
            } else {
              continueWatchingItems.add(ContinueWatchingItem(history: history));
            }
          } catch (e) {
            debugPrint('Error fetching next episode: $e');
            continueWatchingItems.add(ContinueWatchingItem(history: history));
          }
        } else {
          continueWatchingItems.add(ContinueWatchingItem(history: history));
        }
      }
      
      final cached = <String>{};
      for (final item in continueWatchingItems) {
        final cachedEpisode = await _cacheService.getCachedEpisode(
          item.history.animeId,
          item.history.animeTitle,
          item.displayEpisodeNumber,
          item.history.category,
        );
        if (cachedEpisode != null) {
          cached.add('${item.history.animeId}_${item.displayEpisodeNumber}_${item.history.category}');
        }
      }
      
      if (mounted) {
        setState(() {
          _continueWatching = continueWatchingItems;
          _cachedEpisodes = cached;
          _isLoadingContinueWatching = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading continue watching: $e');
      if (mounted) {
        setState(() => _isLoadingContinueWatching = false);
      }
    }
  }

  void _navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );
  }

  void _openProfileMenu() async {
    final profileService = ProfileService();
    final result = await FocusableMenu.show<String>(
      context: context,
      header: Row(
        children: [
          Icon(Icons.person, color: AppColors.neonYellow, size: 20),
          const SizedBox(width: 8),
          Text(
            profileService.currentProfile?.name ?? 'Profile',
            style: const TextStyle(
              color: AppColors.neonYellow,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      items: [
        const FocusableMenuEntry(
          label: 'Downloads',
          icon: Icons.download_done,
          value: 'downloads',
        ),
        const FocusableMenuEntry(
          label: 'Watch History',
          icon: Icons.history,
          value: 'history',
        ),
        FocusableMenuEntry<String>.divider(),
        const FocusableMenuEntry(
          label: 'Switch Profile',
          icon: Icons.swap_horiz,
          value: 'switch',
        ),
        FocusableMenuEntry<String>.divider(),
        FocusableMenuEntry(
          label: 'Logout',
          icon: Icons.logout,
          value: 'logout',
          iconColor: AppColors.error,
          textColor: AppColors.error,
        ),
      ],
    );

    if (result != null && mounted) {
      if (result == 'downloads') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadsScreen()));
      } else if (result == 'history') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const WatchHistoryScreen()));
      } else if (result == 'switch') {
        await profileService.logout();
        if (mounted) Navigator.of(context).pushReplacementNamed('/');
      } else if (result == 'logout') {
        await profileService.logout();
        if (mounted) Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedGradientBackground(
        child: Stack(
          children: [
            Consumer<AnimeProvider>(
              builder: (context, provider, child) {
                if (provider.isLoadingHome) {
                  return _buildLoadingState();
                }

                return CustomScrollView(
                  slivers: [
                    _buildAppBar(),
                    if (provider.spotlight.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSpotlightSection(provider.spotlight)),
                    if (_continueWatching.isNotEmpty)
                      SliverToBoxAdapter(child: _buildContinueWatchingSection()),
                    if (provider.trending.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Trending', provider.trending, '🔥')),
                    if (provider.topAiring.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Top Airing', provider.topAiring, '📺')),
                    if (provider.latest.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Latest Episodes', provider.latest, '🆕')),
                    if (provider.popular.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Most Popular', provider.popular, '⭐')),
                    if (provider.favorite.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Most Favorite', provider.favorite, '❤️')),
                    if (provider.completed.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSection('Recently Completed', provider.completed, '✅')),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final profileService = ProfileService();
    final profile = profileService.currentProfile;
    
    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.95),
      elevation: 0,
      toolbarHeight: 60,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.neonYellowGlass,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neonYellowGlassBorder),
            ),
            child: Icon(Icons.auto_awesome, color: AppColors.neonYellow, size: 20),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ATOM',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Text(
                    ' ANIME',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        // Search button - navigates to full search screen (works on all devices)
        FocusableWidget(
          onSelect: _navigateToSearch,
          builder: (context, isFocused, isHovered) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isFocused ? AppColors.neonYellow : AppColors.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                  width: isFocused ? 2 : 1,
                ),
                boxShadow: isFocused ? [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ] : null,
              ),
              child: Icon(
                Icons.search,
                color: isFocused ? AppColors.background : AppColors.textPrimary,
                size: 20,
              ),
            );
          },
        ),
        // Profile menu button
        if (profile != null)
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: IconButton(
              onPressed: () {
                debugPrint('Profile icon tapped');
                _openProfileMenu();
              },
              tooltip: 'Profile',
              icon: CircleAvatar(
                radius: 18,
                backgroundColor: Color(int.parse((profile.avatarColor ?? '#FFD700').replaceFirst('#', '0xFF'))),
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpotlightSection(List<Anime> spotlight) {
    if (spotlight.isEmpty) return const SizedBox.shrink();
    final anime = spotlight[0];
    
    return Container(
      height: 480,
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // Background image with gradient overlay
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: anime.coverImage ?? '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: AppColors.surface),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surface,
                      child: Icon(Icons.movie, color: AppColors.textMuted, size: 80),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          AppColors.background.withValues(alpha: 0.95),
                          AppColors.background.withValues(alpha: 0.7),
                          AppColors.background.withValues(alpha: 0.3),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.8),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content
          Positioned(
            left: 40,
            top: 40,
            bottom: 40,
            width: MediaQuery.of(context).size.width * 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Featured badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neonYellowGlass,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.neonYellowGlassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.neonYellow,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Featured Anime', style: TextStyle(color: AppColors.neonYellow, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  anime.title,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 42, fontWeight: FontWeight.bold, height: 1.1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                // Meta info
                Row(
                  children: [
                    if (anime.averageScore != null) ...[
                      Icon(Icons.star, color: AppColors.neonYellow, size: 18),
                      const SizedBox(width: 4),
                      Text((anime.averageScore! / 10).toStringAsFixed(1), style: TextStyle(color: AppColors.neonYellow, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                    ],
                    if (anime.year != null) ...[
                      Icon(Icons.calendar_today, color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Text('${anime.year}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(width: 16),
                    ],
                    if (anime.format != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(anime.format!, style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (anime.description != null)
                  Text(
                    anime.description!.replaceAll(RegExp(r'<[^>]*>'), ''),
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 20),
                if (anime.genres.isNotEmpty)
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: anime.genres.take(4).map((genre) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Text(genre, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    )).toList(),
                  ),
                const SizedBox(height: 28),
                // Watch Now button - focusable
                UniversalButton(
                  label: 'Watch Now',
                  icon: Icons.play_arrow,
                  onPressed: () => _navigateToDetails(anime),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the Continue Watching section using FocusableHorizontalList
  Widget _buildContinueWatchingSection() {
    final tvScale = TvScale.factor(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
          child: Row(
            children: [
              const Text('Continue Watching', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.neonYellow, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)])),
              const Spacer(),
              FocusableWidget(
                onSelect: _loadContinueWatching,
                builder: (context, isFocused, isHovered) {
                  return Icon(Icons.refresh, color: isFocused ? AppColors.neonYellow : AppColors.textMuted, size: 20);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 16 * tvScale, bottom: 16 * tvScale),
          child: Text('Pick up where you left off', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        FocusableHorizontalList(
          itemCount: _continueWatching.length,
          itemWidth: 165 * tvScale,
          itemSpacing: 12 * tvScale,
          height: 260 * tvScale,
          sectionLabel: 'continue_watching',
          padding: EdgeInsets.symmetric(horizontal: 12 * tvScale),
          itemBuilder: (context, index, isFocused) {
            return _buildContinueWatchingCard(_continueWatching[index], isFocused);
          },
        ),
      ],
    );
  }

  Widget _buildContinueWatchingCard(ContinueWatchingItem item, bool isFocused) {
    final history = item.history;
    final cacheKey = '${history.animeId}_${item.displayEpisodeNumber}_${history.category}';
    final isCached = _cachedEpisodes.contains(cacheKey);
    final tvScale = TvScale.factor(context);
    final isNextEpisode = item.isNextEpisode;
    final badgeColor = isNextEpisode ? AppColors.success : (history.category == 'dub' ? AppColors.dub : AppColors.sub);
    final badgeText = isNextEpisode ? 'NEXT EP ${item.displayEpisodeNumber}' : 'EP ${item.displayEpisodeNumber}';
    
    return GestureDetector(
      onTap: () => _resumeWatching(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isFocused ? Matrix4.diagonal3Values(1.05, 1.05, 1) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12 * tvScale),
                  border: Border.all(
                    color: isFocused ? AppColors.neonYellow : (isNextEpisode ? AppColors.success.withValues(alpha: 0.6) : AppColors.cardBorder), 
                    width: isFocused ? 3 * tvScale : ((isNextEpisode ? 2 : 1.5) * tvScale),
                  ),
                  boxShadow: isFocused
                      ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.4), blurRadius: 20 * tvScale, spreadRadius: 2 * tvScale)]
                      : [BoxShadow(color: isNextEpisode ? AppColors.success.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05), blurRadius: (isNextEpisode ? 15 : 10) * tvScale)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: history.coverImage ?? '',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AppColors.surface, child: Center(child: CircularProgressIndicator(color: AppColors.neonYellow, strokeWidth: 2))),
                        errorWidget: (context, url, error) => Container(color: AppColors.surface, child: Icon(Icons.movie, color: AppColors.textMuted, size: 40)),
                      ),
                      Container(color: AppColors.background.withValues(alpha: 0.3)),
                      if (isFocused)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.neonYellow.withValues(alpha: 0.2)]),
                          ),
                        ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isFocused ? AppColors.neonYellow : (isNextEpisode ? AppColors.success : AppColors.neonYellow),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: isFocused ? AppColors.neonYellow.withValues(alpha: 0.6) : (isNextEpisode ? AppColors.success.withValues(alpha: 0.5) : AppColors.neonGlowStrong), blurRadius: 20)],
                          ),
                          child: Icon(isNextEpisode ? Icons.skip_next : Icons.play_arrow, color: AppColors.background, size: 26),
                        ),
                      ),
                      Positioned(top: 8, right: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                        child: Text(badgeText, style: TextStyle(color: AppColors.background, fontSize: 9, fontWeight: FontWeight.bold)),
                      )),
                      Positioned(top: 8, left: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: isCached ? AppColors.success : AppColors.surface.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isCached ? Icons.download_done : Icons.cloud_download, color: isCached ? AppColors.background : AppColors.textSecondary, size: 10),
                          const SizedBox(width: 3),
                          Text(isCached ? 'Cached' : 'Stream', style: TextStyle(color: isCached ? AppColors.background : AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.bold)),
                        ]),
                      )),
                      if (!isNextEpisode)
                        Positioned(bottom: 0, left: 0, right: 0, child: Container(
                          height: 4, color: AppColors.surface,
                          child: FractionallySizedBox(widthFactor: history.progress, alignment: Alignment.centerLeft, child: Container(decoration: BoxDecoration(color: AppColors.neonYellow, boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 4)]))),
                        )),
                      if (isNextEpisode)
                        Positioned(bottom: 0, left: 0, right: 0, child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4), color: AppColors.success.withValues(alpha: 0.9),
                          child: const Center(child: Text('UP NEXT', style: TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                        )),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              history.animeTitle,
              style: TextStyle(color: isFocused ? AppColors.neonYellow : AppColors.textPrimary, fontSize: 13, fontWeight: isFocused ? FontWeight.bold : FontWeight.w500),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resumeWatching(ContinueWatchingItem item) async {
    final history = item.history;
    final episodeId = item.nextEpisodeId ?? history.episodeId;
    final episodeNumber = item.displayEpisodeNumber;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    String? localFilePath;
    
    if (!isMobile) {
      final cacheService = DownloadCacheService();
      final cached = await cacheService.getCachedEpisode(history.animeId, history.animeTitle, episodeNumber, history.category);
      localFilePath = cached?.filePath;
      
      if (localFilePath == null) {
        if (!mounted) return;
        final result = await CachingProgressDialog.showAndCache(
          context: context, animeId: history.animeId, animeTitle: history.animeTitle,
          episodeId: episodeId, episodeNumber: episodeNumber, category: history.category, coverImage: history.coverImage,
        );
        if (result == null || !mounted) return;
        localFilePath = result.filePath;
      }
    }
    
    if (!mounted) return;
    
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => VideoPlayerScreen(
        episodeId: episodeId, episodeTitle: 'Episode $episodeNumber', category: history.category,
        episodeNumber: episodeNumber, animeId: history.animeId, animeTitle: history.animeTitle,
        coverImage: history.coverImage, localFilePath: localFilePath,
      ),
    )).then((_) => _loadContinueWatching());
  }

  Widget _buildSection(String title, List<Anime> animeList, String emoji) {
    final tvScale = TvScale.factor(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.neonYellow, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)])),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 16 * tvScale, bottom: 16 * tvScale),
          child: Text(_getSectionSubtitle(title), style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        FocusableHorizontalList(
          itemCount: animeList.length,
          itemWidth: 165 * tvScale,
          itemSpacing: 12 * tvScale,
          height: 260 * tvScale,
          sectionLabel: title.toLowerCase().replaceAll(' ', '_'),
          padding: EdgeInsets.symmetric(horizontal: 12 * tvScale),
          itemBuilder: (context, index, isFocused) {
            return _buildAnimeCard(animeList[index], isFocused);
          },
        ),
      ],
    );
  }

  String _getSectionSubtitle(String title) {
    if (title.contains('Trending')) return 'Most popular anime this week';
    if (title.contains('Airing')) return 'Currently airing anime';
    if (title.contains('Latest')) return 'Recently updated episodes';
    if (title.contains('Popular')) return 'All-time fan favorites';
    if (title.contains('Favorite')) return 'Highest rated by fans';
    if (title.contains('Completed')) return 'Finished series to binge';
    return '';
  }

  Widget _buildAnimeCard(Anime anime, bool isFocused) {
    final tvScale = TvScale.factor(context);
    
    return GestureDetector(
      onTap: () => _navigateToDetails(anime),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isFocused ? Matrix4.diagonal3Values(1.05, 1.05, 1) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12 * tvScale),
                  border: Border.all(
                    color: isFocused ? AppColors.neonYellow : AppColors.cardBorder,
                    width: isFocused ? 3 * tvScale : 1.5 * tvScale,
                  ),
                  boxShadow: isFocused
                      ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.4), blurRadius: 20 * tvScale, spreadRadius: 2 * tvScale)]
                      : [BoxShadow(color: Colors.white.withValues(alpha: 0.05), blurRadius: 10 * tvScale, spreadRadius: -2 * tvScale)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: anime.coverImage ?? '',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AppColors.surface, child: Center(child: CircularProgressIndicator(color: AppColors.neonYellow, strokeWidth: 2))),
                        errorWidget: (context, url, error) => Container(color: AppColors.surface, child: Icon(Icons.movie, color: AppColors.textMuted, size: 40)),
                      ),
                      if (isFocused)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.neonYellow.withValues(alpha: 0.2)]),
                          ),
                        ),
                      if (anime.averageScore != null)
                        Positioned(top: 8, left: 8, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.star, color: AppColors.neonYellow, size: 12),
                            const SizedBox(width: 3),
                            Text((anime.averageScore! / 10).toStringAsFixed(1), style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                          ]),
                        )),
                      if (anime.subEpisodes != null || anime.dubEpisodes != null)
                        Positioned(top: 8, right: 8, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                          child: Text('EP ${anime.subEpisodes ?? anime.dubEpisodes}', style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        )),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              anime.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: isFocused ? AppColors.neonYellow : AppColors.textPrimary, fontSize: 13, fontWeight: isFocused ? FontWeight.bold : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetails(Anime anime) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AnimeDetailsScreen(anime: anime)));
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        _buildAppBar(),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Shimmer.fromColors(
                baseColor: AppColors.surface,
                highlightColor: AppColors.backgroundSecondary,
                child: Container(height: 240, margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20))),
              ),
              for (int i = 0; i < 3; i++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                  child: Shimmer.fromColors(
                    baseColor: AppColors.surface,
                    highlightColor: AppColors.backgroundSecondary,
                    child: Container(height: 24, width: 150, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6))),
                  ),
                ),
                SizedBox(
                  height: 210,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      return Shimmer.fromColors(
                        baseColor: AppColors.surface,
                        highlightColor: AppColors.backgroundSecondary,
                        child: Container(
                          width: 135,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Container(decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)))),
                              const SizedBox(height: 8),
                              Container(height: 12, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(height: 4),
                              Container(height: 12, width: 80, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(4))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
