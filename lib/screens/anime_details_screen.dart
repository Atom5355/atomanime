import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/profile.dart';
import '../providers/anime_provider.dart';
import '../services/download_cache_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;
import 'video_player_screen.dart';

class AnimeDetailsScreen extends StatefulWidget {
  final Anime anime;

  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> with TickerProviderStateMixin {
  String _selectedCategory = 'sub';
  
  // Download tracking
  final DownloadCacheService _cacheService = DownloadCacheService();
  Set<String> _downloadedEpisodes = {};
  final Map<String, double> _downloadingEpisodes = {};
  
  // Watch progress tracking
  final ProfileService _profileService = ProfileService();
  Map<int, WatchHistory> _episodeProgress = {};

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  // Episode search and pagination
  final TextEditingController _episodeSearchController = TextEditingController();
  final FocusNode _episodeSearchFocusNode = FocusNode();
  bool _isSearchExpanded = false;
  String _episodeSearchQuery = '';
  int _visibleEpisodeCount = 20;
  static const int _episodesPerPage = 20;

  // Animation controllers
  late AnimationController _searchAnimController;
  late Animation<double> _searchWidthAnim;
  late AnimationController _countdownAnimController;

  @override
  void initState() {
    super.initState();
    
    // Search animation
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _searchWidthAnim = Tween<double>(begin: 42, end: 220).animate(
      CurvedAnimation(parent: _searchAnimController, curve: Curves.easeOutCubic),
    );

    // Countdown animation (static, no breathing)
    _countdownAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AnimeProvider>(context, listen: false);
      provider.loadAnimeDetails(widget.anime.id);
      provider.loadEpisodes(widget.anime.id);
      _checkDownloadedEpisodes();
      _loadEpisodeProgress();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _episodeSearchController.dispose();
    _episodeSearchFocusNode.dispose();
    _searchAnimController.dispose();
    _countdownAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodeProgress() async {
    if (!_profileService.isLoggedIn) return;
    
    final progress = await _profileService.getAnimeProgress(
      widget.anime.id,
      _selectedCategory,
    );
    
    if (mounted) {
      setState(() {
        _episodeProgress = progress;
      });
    }
  }
  
  Future<void> _checkDownloadedEpisodes() async {
    final cached = await _cacheService.getCachedEpisodesForAnime(
      widget.anime.id,
      widget.anime.title,
    );
    
    setState(() {
      _downloadedEpisodes = cached
        .map((e) => '${e.episodeNumber}_${e.category}')
        .toSet();
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (_isSearchExpanded) {
        _searchAnimController.forward();
        _episodeSearchFocusNode.requestFocus();
      } else {
        _searchAnimController.reverse();
        _episodeSearchController.clear();
        _episodeSearchQuery = '';
      }
    });
  }

  void _loadMoreEpisodes() {
    setState(() {
      _visibleEpisodeCount += _episodesPerPage;
    });
  }

  List<Episode> _filterEpisodes(List<Episode> episodes) {
    // Filter by search query if present
    if (_episodeSearchQuery.isEmpty) return episodes;
    
    final query = _episodeSearchQuery.toLowerCase();
    return episodes.where((ep) {
      final title = ep.title?.toLowerCase() ?? '';
      final number = ep.number.toString();
      return title.contains(query) || number.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AnimeProvider>(
      builder: (context, provider, child) {
        final anime = provider.currentAnimeDetails ?? widget.anime;
        
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              const AnimatedGradientBackground(),
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Infinite scroll: load more when near bottom
                  if (notification is ScrollUpdateNotification) {
                    final maxScroll = notification.metrics.maxScrollExtent;
                    final currentScroll = notification.metrics.pixels;
                    if (currentScroll >= maxScroll - 300) {
                      _loadMoreEpisodes();
                    }
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // Top padding for status bar
                    SliverToBoxAdapter(
                      child: SizedBox(height: MediaQuery.of(context).padding.top + 60),
                    ),
                    // Header section: poster left, info right
                    SliverToBoxAdapter(
                      child: _buildHeaderSection(anime),
                    ),
                    // Seasons section
                    if (anime.relatedSeasons.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildSeasonsSection(anime),
                      ),
                    // Episodes grid header
                    SliverToBoxAdapter(
                      child: _buildEpisodesHeader(anime, provider),
                    ),
                    // Episodes grid with infinite scroll
                    _buildEpisodesGrid(anime, provider),
                    // Bottom padding
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 40),
                    ),
                  ],
                ),
              ),
              // Floating back button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 12,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Header section with poster on left, info on right
  Widget _buildHeaderSection(Anime anime) {
    final posterImage = widget.anime.coverImage ?? anime.coverImage ?? '';
    final tvScale = TvScale.factor(context);
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * tvScale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster image (left side)
          Hero(
            tag: 'anime_poster_${anime.id}',
            child: Container(
              width: 160 * tvScale,
              height: 230 * tvScale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12 * tvScale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12 * tvScale),
                child: CachedNetworkImage(
                  imageUrl: posterImage,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: AppColors.surface),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.surface,
                    child: Icon(Icons.movie, color: AppColors.textMuted, size: 50 * tvScale),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 20 * tvScale),
          // Info section (right side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  anime.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22 * tvScale,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 12 * tvScale),
                // Rating and meta chips
                Wrap(
                  spacing: 8 * tvScale,
                  runSpacing: 8 * tvScale,
                  children: [
                    if (anime.averageScore != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * tvScale, vertical: 5 * tvScale),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(8 * tvScale),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonYellow.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, color: AppColors.background, size: 14 * tvScale),
                            SizedBox(width: 4 * tvScale),
                            Text(
                              (anime.averageScore! / 10).toStringAsFixed(1),
                              style: TextStyle(color: AppColors.background, fontSize: 13 * tvScale, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    if (anime.year != null)
                      _buildMetaChip(anime.year.toString(), tvScale: tvScale),
                    if (anime.format != null)
                      _buildMetaChip(anime.format!, tvScale: tvScale),
                    if (anime.status != null)
                      _buildMetaChip(
                        anime.status!,
                        isHighlighted: anime.status?.toLowerCase() == 'currently airing',
                        tvScale: tvScale,
                      ),
                  ],
                ),
                SizedBox(height: 12 * tvScale),
                // Genres
                if (anime.genres.isNotEmpty)
                  Wrap(
                    spacing: 6 * tvScale,
                    runSpacing: 6 * tvScale,
                    children: anime.genres.take(4).map((genre) {
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * tvScale, vertical: 4 * tvScale),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(16 * tvScale),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          genre,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11 * tvScale),
                        ),
                      );
                    }).toList(),
                  ),
                // Countdown timer (if airing)
                if (anime.status?.toLowerCase() == 'currently airing') ...[
                  SizedBox(height: 14 * tvScale),
                  _buildCompactCountdown(anime),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact countdown widget for header
  Widget _buildCompactCountdown(Anime anime) {
    final nextAiring = anime.nextAiringEpisode ?? _getSimulatedNextAiring(anime);
    if (nextAiring == null || nextAiring.hasAired) return const SizedBox.shrink();

    return _CompactCountdownTimer(nextAiring: nextAiring);
  }

  NextAiringEpisode? _getSimulatedNextAiring(Anime anime) {
    // Simulate next episode timing for ongoing anime
    // In production, this would come from the API
    if (anime.status?.toLowerCase() != 'currently airing') return null;
    
    final currentEpisodes = anime.subEpisodes ?? anime.episodes ?? 0;
    if (currentEpisodes == 0) return null;

    // Simulate next episode in 3-7 days from now
    final now = DateTime.now();
    final daysUntilNext = (now.weekday % 7) + 1; // Random-ish day based on weekday
    final nextAirDate = DateTime(
      now.year, now.month, now.day + daysUntilNext,
      18, 0, 0, // 6 PM
    );

    return NextAiringEpisode(
      episodeNumber: currentEpisodes + 1,
      airingTime: nextAirDate,
    );
  }

  Widget _buildMetaChip(String text, {bool isHighlighted = false, double tvScale = 1.0}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * tvScale, vertical: 5 * tvScale),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.neonYellow.withValues(alpha: 0.15) : AppColors.glass,
        borderRadius: BorderRadius.circular(6 * tvScale),
        border: Border.all(
          color: isHighlighted ? AppColors.neonYellow.withValues(alpha: 0.4) : AppColors.glassBorder,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isHighlighted ? AppColors.neonYellow : AppColors.textMuted,
          fontSize: 12 * tvScale,
          fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildSeasonsSection(Anime anime) {
    final tvScale = TvScale.factor(context);
    return Padding(
      padding: EdgeInsets.only(top: 24 * tvScale, bottom: 8 * tvScale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20 * tvScale),
            child: Row(
              children: [
                Container(
                  width: 4 * tvScale,
                  height: 20 * tvScale,
                  decoration: BoxDecoration(
                    color: AppColors.neonYellow,
                    borderRadius: BorderRadius.circular(2 * tvScale),
                  ),
                ),
                SizedBox(width: 10 * tvScale),
                Text(
                  'Seasons',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18 * tvScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14 * tvScale),
          SizedBox(
            height: 140 * tvScale,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16 * tvScale),
              itemCount: anime.relatedSeasons.length,
              itemBuilder: (context, index) {
                final season = anime.relatedSeasons[index];
                return _buildSeasonCard(season, tvScale);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonCard(RelatedSeason season, double tvScale) {
    final isCurrent = season.isCurrent;
    
    return GestureDetector(
      onTap: isCurrent ? null : () => _navigateToSeason(season),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100 * tvScale,
        margin: EdgeInsets.only(right: 12 * tvScale),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12 * tvScale),
          border: Border.all(
            color: isCurrent ? AppColors.neonYellow : AppColors.cardBorder,
            width: isCurrent ? 2 : 1,
          ),
          boxShadow: isCurrent ? [
            BoxShadow(
              color: AppColors.neonYellow.withValues(alpha: 0.2),
              blurRadius: 10,
            ),
          ] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11 * tvScale),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: season.poster ?? '',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: AppColors.surface),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surface,
                  child: Icon(Icons.movie, color: AppColors.textMuted, size: 24 * tvScale),
                ),
              ),
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
              // Season label
              Positioned(
                bottom: 8 * tvScale,
                left: 8 * tvScale,
                right: 8 * tvScale,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * tvScale, vertical: 2 * tvScale),
                        margin: EdgeInsets.only(bottom: 4 * tvScale),
                        decoration: BoxDecoration(
                          color: AppColors.neonYellow,
                          borderRadius: BorderRadius.circular(4 * tvScale),
                        ),
                        child: Text(
                          'CURRENT',
                          style: TextStyle(
                            color: AppColors.background,
                            fontSize: 8 * tvScale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      season.season ?? season.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? AppColors.neonYellow : AppColors.textPrimary,
                        fontSize: 11 * tvScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToSeason(RelatedSeason season) {
    // Navigate to the selected season
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeDetailsScreen(
          anime: Anime(
            id: season.id,
            title: season.title,
            coverImage: season.poster,
          ),
        ),
      ),
    );
  }

  /// Episodes header with title, search, and sub/dub toggle
  Widget _buildEpisodesHeader(Anime anime, AnimeProvider provider) {
    final hasSub = (anime.subEpisodes ?? 0) > 0;
    final hasDub = (anime.dubEpisodes ?? 0) > 0;
    final tvScale = TvScale.factor(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * tvScale, 24 * tvScale, 20 * tvScale, 14 * tvScale),
      child: Row(
        children: [
          Container(
            width: 4 * tvScale,
            height: 20 * tvScale,
            decoration: BoxDecoration(
              color: AppColors.neonYellow,
              borderRadius: BorderRadius.circular(2 * tvScale),
            ),
          ),
          SizedBox(width: 10 * tvScale),
          Text(
            'Episodes',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18 * tvScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Episode search
          AnimatedBuilder(
            animation: _searchWidthAnim,
            builder: (context, child) {
              final hasActiveSearch = _episodeSearchQuery.isNotEmpty;
              
              return Container(
                width: _searchWidthAnim.value * tvScale,
                height: 38 * tvScale,
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(19 * tvScale),
                  border: Border.all(
                    color: hasActiveSearch
                        ? AppColors.neonYellow.withValues(alpha: 0.6)
                        : AppColors.glassBorder,
                    width: hasActiveSearch ? 1.5 : 1,
                  ),
                  boxShadow: hasActiveSearch ? [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ] : null,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleSearch,
                      child: Container(
                        width: 38 * tvScale,
                        height: 38 * tvScale,
                        alignment: Alignment.center,
                        child: Icon(
                          _isSearchExpanded ? Icons.close : Icons.search,
                          color: AppColors.textPrimary,
                          size: 18 * tvScale,
                        ),
                      ),
                    ),
                    if (_isSearchExpanded)
                      Expanded(
                        child: TextField(
                          controller: _episodeSearchController,
                          focusNode: _episodeSearchFocusNode,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13 * tvScale,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search episodes...',
                            hintStyle: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13 * tvScale,
                              fontWeight: FontWeight.normal,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10 * tvScale),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _episodeSearchQuery = value;
                              _visibleEpisodeCount = _episodesPerPage;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          SizedBox(width: 10 * tvScale),
          // Sub/Dub Toggle
          if (hasSub || hasDub)
            GlassCard(
              padding: EdgeInsets.all(4 * tvScale),
              borderRadius: 10 * tvScale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSub)
                    _buildCategoryButton('SUB', 'sub', anime.subEpisodes),
                  if (hasDub)
                    _buildCategoryButton('DUB', 'dub', anime.dubEpisodes),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Responsive episodes grid with infinite scroll
  Widget _buildEpisodesGrid(Anime anime, AnimeProvider provider) {
    var allEpisodes = provider.episodes;
    
    // Limit episodes based on selected category
    // The API returns all episodes, but anime info tells us how many are sub/dub
    if (_selectedCategory == 'sub' && anime.subEpisodes != null) {
      allEpisodes = allEpisodes.take(anime.subEpisodes!).toList();
    } else if (_selectedCategory == 'dub' && anime.dubEpisodes != null) {
      allEpisodes = allEpisodes.take(anime.dubEpisodes!).toList();
    }
    
    final filteredEpisodes = _filterEpisodes(allEpisodes);
    final displayedEpisodes = filteredEpisodes.take(_visibleEpisodeCount).toList();

    if (provider.isLoadingEpisodes) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: CircularProgressIndicator(color: AppColors.neonYellow),
          ),
        ),
      );
    }

    if (allEpisodes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text(
              'No episodes available',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    if (filteredEpisodes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.search_off, color: AppColors.textMuted, size: 40),
                const SizedBox(height: 10),
                Text(
                  'No episodes match "$_episodeSearchQuery"',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tvScale = TvScale.factor(context);
    
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16 * tvScale),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          // Calculate grid columns based on available width
          final availableWidth = constraints.crossAxisExtent;
          final columns = _calculateColumns(availableWidth);
          final cardWidth = (availableWidth - (columns - 1) * 12 * tvScale) / columns;
          
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12 * tvScale,
              crossAxisSpacing: 12 * tvScale,
              childAspectRatio: _calculateAspectRatio(cardWidth),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final episode = displayedEpisodes[index];
                return _EpisodeGridCard(
                  key: ValueKey('episode_${episode.id}_${episode.number}'),
                  episode: episode,
                  index: index,
                  isDownloaded: _downloadedEpisodes.contains('${episode.number}_$_selectedCategory'),
                  isDownloading: _downloadingEpisodes.containsKey('${episode.number}_$_selectedCategory'),
                  downloadProgress: _downloadingEpisodes['${episode.number}_$_selectedCategory'] ?? 0,
                  watchProgress: _episodeProgress[episode.number],
                  selectedCategory: _selectedCategory,
                  onPlay: () => _playEpisode(episode),
                );
              },
              childCount: displayedEpisodes.length,
            ),
          );
        },
      ),
    );
  }

  /// Calculate number of columns based on screen width
  int _calculateColumns(double width) {
    if (width > 1400) return 6;
    if (width > 1100) return 5;
    if (width > 800) return 4;
    if (width > 600) return 3;
    if (width > 400) return 2;
    return 2;
  }

  /// Calculate aspect ratio for episode cards
  double _calculateAspectRatio(double cardWidth) {
    // Cards should be roughly 16:9 with some room for info
    if (cardWidth > 200) return 1.4;
    if (cardWidth > 150) return 1.3;
    return 1.2;
  }

  Widget _buildCategoryButton(String label, String category, int? count) {
    final isSelected = _selectedCategory == category;
    final isSub = category == 'sub';
    final color = isSub ? AppColors.sub : AppColors.dub;
    final tvScale = TvScale.factor(context);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = category;
        });
        _loadEpisodeProgress();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12 * tvScale, vertical: 6 * tvScale),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.7)])
              : null,
          borderRadius: BorderRadius.circular(6 * tvScale),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.background : AppColors.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12 * tvScale,
              ),
            ),
            if (count != null) ...[
              SizedBox(width: 3 * tvScale),
              Text(
                '($count)',
                style: TextStyle(
                  color: isSelected ? AppColors.background.withValues(alpha: 0.8) : AppColors.textMuted,
                  fontSize: 10 * tvScale,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _playEpisode(Episode episode) async {
    final key = '${episode.number}_$_selectedCategory';
    final isDownloaded = _downloadedEpisodes.contains(key);
    
    // On mobile platforms, skip caching and stream directly (HLS streams can't be downloaded via HTTP)
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    if (!isMobile && !isDownloaded) {
      final success = await _downloadEpisode(episode);
      if (!success || !mounted) return;
    }
    
    CachedEpisode? cached;
    if (!isMobile) {
      cached = await _cacheService.getCachedEpisode(
        widget.anime.id,
        widget.anime.title,
        episode.number,
        _selectedCategory,
      );
    }
    
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          episodeId: episode.id,
          episodeTitle: episode.title ?? 'Episode ${episode.number}',
          category: _selectedCategory,
          episodeNumber: episode.number,
          animeId: widget.anime.id,
          animeTitle: widget.anime.title,
          coverImage: widget.anime.coverImage,
          localFilePath: cached?.filePath,
        ),
      ),
    );
  }
  
  Future<bool> _downloadEpisode(Episode episode) async {
    final key = '${episode.number}_$_selectedCategory';
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CachingProgressDialog(
        animeTitle: widget.anime.title,
        episodeNumber: episode.number,
        onDownload: (onProgress) async {
          final cached = await _cacheService.downloadEpisode(
            animeId: widget.anime.id,
            animeTitle: widget.anime.title,
            episodeId: episode.id,
            episodeNumber: episode.number,
            category: _selectedCategory,
            coverImage: widget.anime.coverImage,
            onProgress: onProgress,
          );
          return cached;
        },
      ),
    );
    
    if (result == true && mounted) {
      setState(() {
        _downloadedEpisodes.add(key);
      });
    }
    
    return result == true;
  }
}

/// Countdown timer card widget
class _CountdownTimerCard extends StatefulWidget {
  final NextAiringEpisode nextAiring;
  final AnimationController animationController;

  const _CountdownTimerCard({
    required this.nextAiring,
    required this.animationController,
  });

  @override
  State<_CountdownTimerCard> createState() => _CountdownTimerCardState();
}

class _CountdownTimerCardState extends State<_CountdownTimerCard> {
  late Timer _timer;
  Duration _timeRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateTimeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeRemaining();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTimeRemaining() {
    setState(() {
      _timeRemaining = widget.nextAiring.timeUntilAiring;
    });
  }

  String _formatCountdown() {
    if (_timeRemaining.isNegative) return '00:00:00';
    
    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours.remainder(24);
    final minutes = _timeRemaining.inMinutes.remainder(60);
    final seconds = _timeRemaining.inSeconds.remainder(60);
    
    if (days > 0) {
      return '${days}d ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatAiringDate() {
    final local = widget.nextAiring.airingTime.toLocal();
    final weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][local.weekday % 7];
    final month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][local.month - 1];
    final hour = local.hour > 12 ? local.hour - 12 : local.hour;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month ${local.day} at ${hour == 0 ? 12 : hour}:${local.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.neonYellow.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonYellow.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Episode badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'EPISODE ${widget.nextAiring.episodeNumber}',
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Countdown
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.8)],
                ).createShader(bounds),
                child: Text(
                  _formatCountdown(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Airing date subtitle
              Text(
                _formatAiringDate(),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Load more button with animation
class _LoadMoreButton extends StatefulWidget {
  final VoidCallback onTap;
  final int remainingCount;

  const _LoadMoreButton({
    required this.onTap,
    required this.remainingCount,
  });

  @override
  State<_LoadMoreButton> createState() => _LoadMoreButtonState();
}

class _LoadMoreButtonState extends State<_LoadMoreButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _isLoading = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isLoading ? null : _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonYellow,
                ),
              )
            else
              Icon(Icons.expand_more, color: AppColors.neonYellow, size: 18),
            const SizedBox(width: 8),
            Text(
              _isLoading ? 'Loading...' : 'Load ${widget.remainingCount > 20 ? 20 : widget.remainingCount} more',
              style: TextStyle(
                color: AppColors.neonYellow,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple caching progress dialog
class _CachingProgressDialog extends StatefulWidget {
  final String animeTitle;
  final int episodeNumber;
  final Future<CachedEpisode?> Function(
    void Function(double progress, String status) onProgress,
  ) onDownload;

  const _CachingProgressDialog({
    required this.animeTitle,
    required this.episodeNumber,
    required this.onDownload,
  });

  @override
  State<_CachingProgressDialog> createState() => _CachingProgressDialogState();
}

class _CachingProgressDialogState extends State<_CachingProgressDialog> {
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
                Text(
                  'Episode ${widget.episodeNumber}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
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
                        value: _progress > 0 ? _progress : null,
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

/// Compact countdown timer for header section
class _CompactCountdownTimer extends StatefulWidget {
  final NextAiringEpisode nextAiring;

  const _CompactCountdownTimer({required this.nextAiring});

  @override
  State<_CompactCountdownTimer> createState() => _CompactCountdownTimerState();
}

class _CompactCountdownTimerState extends State<_CompactCountdownTimer> {
  late Timer _timer;
  Duration _timeRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateTimeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeRemaining();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTimeRemaining() {
    if (mounted) {
      setState(() {
        _timeRemaining = widget.nextAiring.timeUntilAiring;
      });
    }
  }

  String _formatCountdown() {
    if (_timeRemaining.isNegative) return '00:00:00';
    
    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours.remainder(24);
    final minutes = _timeRemaining.inMinutes.remainder(60);
    final seconds = _timeRemaining.inSeconds.remainder(60);
    
    if (days > 0) {
      return '${days}d ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.8)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'EP ${widget.nextAiring.episodeNumber}',
              style: const TextStyle(
                color: AppColors.background,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.8)],
            ).createShader(bounds),
            child: Text(
              _formatCountdown(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Episode grid card with fade-in animation
class _EpisodeGridCard extends StatefulWidget {
  final Episode episode;
  final int index;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final WatchHistory? watchProgress;
  final String selectedCategory;
  final VoidCallback onPlay;

  const _EpisodeGridCard({
    super.key,
    required this.episode,
    required this.index,
    required this.isDownloaded,
    required this.isDownloading,
    required this.downloadProgress,
    required this.watchProgress,
    required this.selectedCategory,
    required this.onPlay,
  });

  @override
  State<_EpisodeGridCard> createState() => _EpisodeGridCardState();
}

class _EpisodeGridCardState extends State<_EpisodeGridCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + (widget.index % 8) * 50),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    
    // Staggered animation start
    Future.delayed(Duration(milliseconds: (widget.index % 12) * 30), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = widget.selectedCategory == 'sub' ? AppColors.sub : AppColors.dub;
    final hasProgress = widget.watchProgress != null && 
                        widget.watchProgress!.watchedDuration.inSeconds > 0;
    final isCompleted = widget.watchProgress?.completed ?? false;
    final progress = widget.watchProgress?.progress ?? 0;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.surface : AppColors.glass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHovered 
                    ? categoryColor.withValues(alpha: 0.5)
                    : isCompleted
                        ? AppColors.neonYellow.withValues(alpha: 0.3)
                        : AppColors.glassBorder,
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: categoryColor.withValues(alpha: 0.2),
                        blurRadius: 15,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                children: [
                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Episode number badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [categoryColor, categoryColor.withValues(alpha: 0.7)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: categoryColor.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                widget.episode.number.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  color: AppColors.background,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Status indicators
                            if (widget.isDownloading)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  value: widget.downloadProgress,
                                  strokeWidth: 2,
                                  color: AppColors.neonYellow,
                                ),
                              )
                            else if (widget.isDownloaded)
                              Icon(Icons.download_done, 
                                color: AppColors.neonYellow, size: 18)
                            else if (isCompleted)
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: AppColors.neonYellow,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, 
                                  size: 12, color: AppColors.background),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Episode title
                        Expanded(
                          child: Text(
                            widget.episode.title ?? 'Episode ${widget.episode.number}',
                            style: TextStyle(
                              color: _isHovered 
                                  ? AppColors.textPrimary 
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Play button (appears on hover)
                        AnimatedOpacity(
                          opacity: _isHovered ? 1 : 0.7,
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_circle_filled,
                                color: _isHovered ? categoryColor : AppColors.textMuted,
                                size: 24,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.selectedCategory.toUpperCase(),
                                style: TextStyle(
                                  color: _isHovered 
                                      ? categoryColor 
                                      : AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress bar at bottom
                  if (hasProgress && !isCompleted)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(11),
                            bottomRight: Radius.circular(11),
                          ),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.neonYellow,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(11),
                              ),
                            ),
                          ),
                        ),
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
}
