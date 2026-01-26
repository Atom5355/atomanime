import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:ui';
import '../providers/anime_provider.dart';
import '../models/anime.dart';
import '../services/profile_service.dart';
import '../services/download_cache_service.dart';
import '../services/aniwatch_service.dart';
import '../models/profile.dart';
import '../widgets/common_widgets.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;
import 'anime_details_screen.dart';
import 'downloads_screen.dart';
import 'watch_history_screen.dart';
import 'video_player_screen.dart';

/// Wrapper for continue watching items with "next episode" recommendation
class ContinueWatchingItem {
  final WatchHistory history;
  final bool isNextEpisode; // True if we're recommending the next episode
  final int displayEpisodeNumber; // Episode number to show
  final String? nextEpisodeId; // Episode ID for the next episode (if recommending)
  
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _searchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0;
  final ScrollController _searchScrollController = ScrollController();
  final LayerLink _searchLayerLink = LayerLink();
  OverlayEntry? _searchOverlayEntry;
  
  // Continue Watching
  final ProfileService _profileService = ProfileService();
  final DownloadCacheService _cacheService = DownloadCacheService();
  final AniwatchService _aniwatchService = AniwatchService();
  List<ContinueWatchingItem> _continueWatching = [];
  Set<String> _cachedEpisodes = {}; // Track which continue watching items are cached
  bool _isLoadingContinueWatching = false;
  
  // Auto-search debounce timer
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnimeProvider>(context, listen: false).loadHomePage();
      _loadContinueWatching();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeSearchOverlay();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _animationController.dispose();
    _searchScrollController.dispose();
    super.dispose();
  }

  void _removeSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh continue watching when app resumes
    if (state == AppLifecycleState.resumed) {
      _loadContinueWatching();
    }
  }
  
  /// Load continue watching data and check cache status
  /// Groups by anime and shows the most recently watched episode for each
  /// If progress >= 90%, recommends the next episode instead
  Future<void> _loadContinueWatching() async {
    if (_isLoadingContinueWatching) return;
    
    setState(() => _isLoadingContinueWatching = true);
    
    try {
      final results = await _profileService.getContinueWatching(limit: 50);
      
      // Group by anime and pick the most recently watched episode for each
      final grouped = <String, WatchHistory>{};
      for (final history in results) {
        final key = '${history.animeId}_${history.category}';
        if (!grouped.containsKey(key) || 
            history.updatedAt.isAfter(grouped[key]!.updatedAt)) {
          grouped[key] = history;
        }
      }
      
      // Convert back to list and sort by most recent
      final groupedList = grouped.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      
      // Process items: check if we should recommend next episode
      final continueWatchingItems = <ContinueWatchingItem>[];
      
      for (final history in groupedList) {
        // If less than 3 minutes remaining, recommend next episode instead
        final remaining = history.totalDuration - history.watchedDuration;
        final isNearEnd = remaining <= const Duration(minutes: 3) && remaining > Duration.zero;
        
        if (isNearEnd) {
          // Try to fetch next episode info
          try {
            final episodes = await _aniwatchService.getEpisodes(history.animeId);
            final nextEpNumber = history.episodeNumber + 1;
            final nextEpisode = episodes.where((e) => e.number == nextEpNumber).firstOrNull;
            
            if (nextEpisode != null) {
              // Recommend next episode
              continueWatchingItems.add(ContinueWatchingItem(
                history: history,
                isNextEpisode: true,
                displayEpisode: nextEpNumber,
                nextEpisodeId: nextEpisode.id,
              ));
            } else {
              // No more episodes, show as regular (user might want to rewatch)
              continueWatchingItems.add(ContinueWatchingItem(history: history));
            }
          } catch (e) {
            // Fallback to regular display on error
            debugPrint('Error fetching next episode: $e');
            continueWatchingItems.add(ContinueWatchingItem(history: history));
          }
        } else {
          continueWatchingItems.add(ContinueWatchingItem(history: history));
        }
      }
      
      // Check cache status for each item
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

  void _openSearch() {
    if (_searchExpanded) return;
    setState(() {
      _searchExpanded = true;
    });
    _showSearchOverlay();
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _showSearchOverlay() {
    final provider = Provider.of<AnimeProvider>(context, listen: false);
    // Only show overlay if searching or has results
    if (!provider.isSearching && provider.searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return;
    }
    
    _removeSearchOverlay();
    _searchOverlayEntry = OverlayEntry(
      builder: (context) => _buildSearchDropdownOverlay(),
    );
    Overlay.of(context).insert(_searchOverlayEntry!);
  }

  void _closeSearch() {
    if (!_searchExpanded) return;
    _animationController.reverse().then((_) {
      _removeSearchOverlay();
      setState(() {
        _searchExpanded = false;
        _selectedIndex = 0;
      });
      _searchController.clear();
      Provider.of<AnimeProvider>(context, listen: false).clearSearch();
    });
  }

  void _handleSearchKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final provider = Provider.of<AnimeProvider>(context, listen: false);
    final results = provider.searchResults;
    
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, results.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, results.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (results.isNotEmpty && _selectedIndex < results.length) {
        _navigateToDetails(results[_selectedIndex]);
        _closeSearch();
      }
    }
  }

  void _scrollToSelected() {
    if (_searchScrollController.hasClients) {
      final itemHeight = 72.0;
      final targetOffset = (_selectedIndex * itemHeight) - 100;
      _searchScrollController.animateTo(
        targetOffset.clamp(0, _searchScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
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
                  // Continue Watching section
                  if (_continueWatching.isNotEmpty)
                    SliverToBoxAdapter(child: _buildContinueWatchingSection()),
                  if (provider.trending.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('🔥 Trending', provider.trending)),
                  if (provider.topAiring.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('📺 Top Airing', provider.topAiring)),
                  if (provider.latest.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('🆕 Latest Episodes', provider.latest)),
                  if (provider.popular.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('⭐ Most Popular', provider.popular)),
                  if (provider.favorite.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('❤️ Most Favorite', provider.favorite)),
                  if (provider.completed.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSection('✅ Recently Completed', provider.completed)),
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

  Widget _buildSearchDropdownOverlay() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final provider = Provider.of<AnimeProvider>(context, listen: false);
        
        // Don't show overlay if no search query or no results/searching
        if (_searchController.text.isEmpty || (!provider.isSearching && provider.searchResults.isEmpty)) {
          return const SizedBox.shrink();
        }
        
        return Stack(
          children: [
            // Background scrim - subtle darkening
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeSearch,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4 * _fadeAnimation.value),
                ),
              ),
            ),
            // Search dropdown positioned under the search bar
            Positioned(
              top: 0,
              right: 8, // Match the search bar's right margin
              child: CompositedTransformFollower(
                link: _searchLayerLink,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, -20 * (1 - _expandAnimation.value)),
                    child: Material(
                      elevation: 0,
                      color: Colors.transparent,
                      child: Container(
                        width: _searchExpanded ? 380 : 220,
                        constraints: const BoxConstraints(maxHeight: 500),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.glassBorder.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: _buildSearchResults(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults() {
    return Consumer<AnimeProvider>(
      builder: (context, provider, child) {
        if (provider.isSearching) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: AppColors.textSecondary,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Searching...',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (provider.searchResults.isEmpty) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, color: AppColors.textMuted, size: 40),
                const SizedBox(height: 12),
                Text(
                  'No results found',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: ListView.builder(
            controller: _searchScrollController,
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            itemCount: provider.searchResults.length,
            itemBuilder: (context, index) {
              return _buildSearchResultItem(provider.searchResults[index], index);
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchResultItem(Anime anime, int index) {
    final isSelected = index == _selectedIndex;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _selectedIndex = index),
      child: GestureDetector(
        onTap: () {
          _navigateToDetails(anime);
          _closeSearch();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected 
                ? AppColors.textPrimary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected 
                ? Border.all(
                    color: AppColors.textPrimary.withValues(alpha: 0.15),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Anime poster
              Hero(
                tag: 'search-${anime.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: anime.coverImage ?? '',
                    width: 50,
                    height: 70,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 50,
                      height: 70,
                      color: AppColors.glass,
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 50,
                      height: 70,
                      color: AppColors.glass,
                      child: Icon(Icons.movie, color: AppColors.textMuted, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? AppColors.neonYellow : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (anime.format != null) ...[
                          _buildInfoChip(anime.format!, AppColors.info),
                          const SizedBox(width: 6),
                        ],
                        if (anime.subEpisodes != null) ...[
                          _buildEpisodeChip('SUB', anime.subEpisodes!, AppColors.sub),
                          const SizedBox(width: 6),
                        ],
                        if (anime.dubEpisodes != null) ...[
                          _buildEpisodeChip('DUB', anime.dubEpisodes!, AppColors.dub),
                          const SizedBox(width: 6),
                        ],
                        if (anime.rating != null) ...[
                          _buildInfoChip(anime.rating!, AppColors.warning),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow indicator for selected
              if (isSelected)
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.neonYellow.withValues(alpha: 0.7),
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEpisodeChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
          // Logo
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
        // Expandable Search bar
        CompositedTransformTarget(
          link: _searchLayerLink,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: _searchExpanded ? 380 : 220,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: _handleSearchKeyEvent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _searchController.text.isNotEmpty
                        ? AppColors.neonYellow.withValues(alpha: 0.6)
                        : AppColors.glassBorder,
                    width: _searchController.text.isNotEmpty ? 1.5 : 1,
                  ),
                  boxShadow: _searchController.text.isNotEmpty ? [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ] : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: AppColors.textPrimary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search anime...',
                          hintStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onTap: _openSearch,
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            setState(() => _selectedIndex = 0);
                            Provider.of<AnimeProvider>(context, listen: false).searchAnime(value);
                            _searchOverlayEntry?.markNeedsBuild();
                          }
                        },
                        onChanged: (value) {
                          setState(() {}); // Rebuild to show border
                          // Update overlay visibility
                          if (_searchExpanded) {
                            _searchOverlayEntry?.markNeedsBuild();
                          }
                          // Auto-search with debounce for Fire TV (no Enter key)
                          _searchDebounce?.cancel();
                          if (value.length >= 3) {
                            _searchDebounce = Timer(const Duration(milliseconds: 800), () {
                              if (value.isNotEmpty && mounted) {
                                setState(() => _selectedIndex = 0);
                                Provider.of<AnimeProvider>(context, listen: false).searchAnime(value);
                                _searchOverlayEntry?.markNeedsBuild();
                              }
                            });
                          }
                        },
                      ),
                    ),
                    if (_searchExpanded && _searchController.text.isNotEmpty) ...[
                      // Search submit button for D-Pad users
                      Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              if (_searchController.text.isNotEmpty) {
                                Provider.of<AnimeProvider>(context, listen: false)
                                    .searchAnime(_searchController.text);
                                _searchOverlayEntry?.markNeedsBuild();
                              }
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final isFocused = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: () {
                                if (_searchController.text.isNotEmpty) {
                                  Provider.of<AnimeProvider>(context, listen: false)
                                      .searchAnime(_searchController.text);
                                  _searchOverlayEntry?.markNeedsBuild();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isFocused ? AppColors.neonYellow : AppColors.glass,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                                    width: isFocused ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  'GO',
                                  style: TextStyle(
                                    color: isFocused ? AppColors.background : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: _closeSearch,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.glass,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Icon(Icons.close, color: AppColors.textMuted, size: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        // Profile
        if (profile != null)
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'downloads') {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadsScreen()));
                } else if (value == 'history') {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const WatchHistoryScreen()));
                } else if (value == 'switch') {
                  await profileService.logout();
                  if (mounted) Navigator.of(context).pushReplacementNamed('/');
                } else if (value == 'logout') {
                  await profileService.logout();
                  if (mounted) Navigator.of(context).pushReplacementNamed('/');
                }
              },
              offset: const Offset(0, 50),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'downloads', child: Row(children: [Icon(Icons.download_done, size: 20), SizedBox(width: 8), Text('Downloads')])),
                const PopupMenuItem(value: 'history', child: Row(children: [Icon(Icons.history, size: 20), SizedBox(width: 8), Text('Watch History')])),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'switch', child: Row(children: [Icon(Icons.swap_horiz, size: 20), SizedBox(width: 8), Text('Switch Profile')])),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 20, color: Colors.red), SizedBox(width: 8), Text('Logout', style: TextStyle(color: Colors.red))])),
              ],
              child: CircleAvatar(
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
    final anime = spotlight[0]; // Featured anime
    
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
                  // Gradient overlay - darker on left for text readability
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
                  // Bottom gradient
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
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.neonYellow,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Featured Anime',
                        style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  anime.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                // Meta info row
                Row(
                  children: [
                    if (anime.averageScore != null) ...[
                      Icon(Icons.star, color: AppColors.neonYellow, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        (anime.averageScore! / 10).toStringAsFixed(1),
                        style: TextStyle(color: AppColors.neonYellow, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (anime.year != null) ...[
                      Icon(Icons.calendar_today, color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Text('${anime.year}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(width: 16),
                    ],
                    Icon(Icons.schedule, color: AppColors.textSecondary, size: 14),
                    const SizedBox(width: 4),
                    Text('24 min', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(width: 16),
                    if (anime.format != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          anime.format!,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Description
                if (anime.description != null)
                  Text(
                    anime.description!.replaceAll(RegExp(r'<[^>]*>'), ''),
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 20),
                // Genre chips
                if (anime.genres.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                // Action buttons
                Row(
                  children: [
                    // Watch Now button - glassmorphism yellow
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _navigateToDetails(anime),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.neonYellow,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: AppColors.neonGlow, blurRadius: 15, spreadRadius: -2),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow, color: AppColors.background, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Watch Now',
                                style: TextStyle(
                                  color: AppColors.background,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the Continue Watching section with resume progress
  Widget _buildContinueWatchingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
          child: Row(
            children: [
              const Text(
                'Continue Watching',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.neonYellow,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
                onPressed: _loadContinueWatching,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: TvScale.scale(context, 16), bottom: TvScale.scale(context, 16)),
          child: Text(
            'Pick up where you left off',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        SizedBox(
          height: TvScale.scale(context, 260),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: TvScale.scale(context, 12)),
            itemCount: _continueWatching.length,
            itemBuilder: (context, index) {
              return _buildContinueWatchingCard(_continueWatching[index]);
            },
          ),
        ),
      ],
    );
  }

  /// Build a continue watching card with progress overlay
  Widget _buildContinueWatchingCard(ContinueWatchingItem item) {
    final history = item.history;
    final cacheKey = '${history.animeId}_${item.displayEpisodeNumber}_${history.category}';
    final isCached = _cachedEpisodes.contains(cacheKey);
    final tvScale = TvScale.factor(context);
    
    // For next episode recommendations, use different styling
    final isNextEpisode = item.isNextEpisode;
    final badgeColor = isNextEpisode ? AppColors.success : (history.category == 'dub' ? AppColors.dub : AppColors.sub);
    final badgeText = isNextEpisode ? 'NEXT EP ${item.displayEpisodeNumber}' : 'EP ${item.displayEpisodeNumber}';
    
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            _resumeWatching(item);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () => _resumeWatching(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 165 * tvScale,
              margin: EdgeInsets.symmetric(horizontal: 6 * tvScale),
              transform: isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
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
                            ? [
                                BoxShadow(
                                  color: AppColors.neonYellow.withValues(alpha: 0.4),
                                  blurRadius: 20 * tvScale,
                                  spreadRadius: 2 * tvScale,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: isNextEpisode 
                                      ? AppColors.success.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.05),
                                  blurRadius: (isNextEpisode ? 15 : 10) * tvScale,
                                  spreadRadius: (isNextEpisode ? 0 : -2) * tvScale,
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: history.coverImage ?? '',
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.surface,
                                child: Center(child: CircularProgressIndicator(color: AppColors.neonYellow, strokeWidth: 2)),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.surface,
                                child: Icon(Icons.movie, color: AppColors.textMuted, size: 40),
                              ),
                            ),
                            // Dark overlay for play button
                            Container(color: AppColors.background.withValues(alpha: 0.3)),
                            // Focus overlay
                            if (isFocused)
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      AppColors.neonYellow.withValues(alpha: 0.2),
                                    ],
                                  ),
                                ),
                              ),
                            // Play button
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isFocused ? AppColors.neonYellow : (isNextEpisode ? AppColors.success : AppColors.neonYellow),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(
                                    color: isFocused ? AppColors.neonYellow.withValues(alpha: 0.6) : (isNextEpisode ? AppColors.success.withValues(alpha: 0.5) : AppColors.neonGlowStrong), 
                                    blurRadius: 20,
                                  )],
                                ),
                                child: Icon(
                                  isNextEpisode ? Icons.skip_next : Icons.play_arrow, 
                                  color: AppColors.background, 
                                  size: 26,
                                ),
                              ),
                            ),
                            // Episode badge - top right
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                          child: Text(
                            badgeText,
                            style: TextStyle(color: AppColors.background, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      // Cached badge - top left
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCached ? AppColors.success : AppColors.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCached ? Icons.download_done : Icons.cloud_download,
                                color: isCached ? AppColors.background : AppColors.textSecondary,
                                size: 10,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isCached ? 'Cached' : 'Stream',
                                style: TextStyle(
                                  color: isCached ? AppColors.background : AppColors.textSecondary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Progress bar at bottom (show progress only if resuming, not for next episode)
                      if (!isNextEpisode)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 4,
                            color: AppColors.surface,
                            child: FractionallySizedBox(
                              widthFactor: history.progress,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.neonYellow,
                                  boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // "Up Next" banner for next episode
                      if (isNextEpisode)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: AppColors.success.withValues(alpha: 0.9),
                            child: const Center(
                              child: Text(
                                'UP NEXT',
                                style: TextStyle(
                                  color: AppColors.background,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
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
            const SizedBox(height: 10),
            Text(
              history.animeTitle,
              style: TextStyle(
                color: isFocused ? AppColors.neonYellow : AppColors.textPrimary, 
                fontSize: 13, 
                fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
        },
      ),
    );
  }

  /// Resume watching from history - ensures episode is cached first (desktop only)
  Future<void> _resumeWatching(ContinueWatchingItem item) async {
    final history = item.history;
    final episodeId = item.nextEpisodeId ?? history.episodeId;
    final episodeNumber = item.displayEpisodeNumber;
    
    // On mobile platforms, skip caching and stream directly (HLS streams can't be downloaded via HTTP)
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    String? localFilePath;
    
    if (!isMobile) {
      final cacheService = DownloadCacheService();
      
      // Check if episode is already cached
      final cached = await cacheService.getCachedEpisode(
        history.animeId,
        history.animeTitle,
        episodeNumber,
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
          episodeId: episodeId,
          episodeNumber: episodeNumber,
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
          episodeId: episodeId,
          episodeTitle: 'Episode $episodeNumber',
          category: history.category,
          episodeNumber: episodeNumber,
          animeId: history.animeId,
          animeTitle: history.animeTitle,
          coverImage: history.coverImage,
          localFilePath: localFilePath,
        ),
      ),
    ).then((_) {
      // Refresh continue watching when returning
      _loadContinueWatching();
    });
  }

  Widget _buildSection(String title, List<Anime> animeList) {
    // Parse title to get emoji and text
    final hasEmoji = title.startsWith(RegExp(r'[^\w\s]'));
    final displayTitle = hasEmoji ? title.substring(2).trim() : title;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
          child: Row(
            children: [
              Text(
                displayTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.neonYellow,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.neonGlow, blurRadius: 6)],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: TvScale.scale(context, 16), bottom: TvScale.scale(context, 16)),
          child: Text(
            _getSectionSubtitle(title),
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        SizedBox(
          height: TvScale.scale(context, 260),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: TvScale.scale(context, 12)),
            itemCount: animeList.length,
            itemBuilder: (context, index) {
              return _buildAnimeCard(animeList[index]);
            },
          ),
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

  Widget _buildAnimeCard(Anime anime) {
    final tvScale = TvScale.factor(context);
    
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle Select/Enter/Space for Fire TV remote
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            _navigateToDetails(anime);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () => _navigateToDetails(anime),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 165 * tvScale,
              margin: EdgeInsets.symmetric(horizontal: 6 * tvScale),
              transform: isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
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
                            ? [
                                BoxShadow(
                                  color: AppColors.neonYellow.withValues(alpha: 0.4),
                                  blurRadius: 20 * tvScale,
                                  spreadRadius: 2 * tvScale,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  blurRadius: 10 * tvScale,
                                  spreadRadius: -2 * tvScale,
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: anime.coverImage ?? '',
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.surface,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.neonYellow,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.surface,
                                child: Icon(Icons.movie, color: AppColors.textMuted, size: 40),
                              ),
                            ),
                            // Focus overlay
                            if (isFocused)
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      AppColors.neonYellow.withValues(alpha: 0.2),
                                    ],
                                  ),
                                ),
                              ),
                            // Rating badge - top left
                            if (anime.averageScore != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, color: AppColors.neonYellow, size: 12),
                                      const SizedBox(width: 3),
                                      Text(
                                        (anime.averageScore! / 10).toStringAsFixed(1),
                                        style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Episode badge - top right
                            if (anime.subEpisodes != null || anime.dubEpisodes != null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'EP ${anime.subEpisodes ?? anime.dubEpisodes}',
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _navigateToDetails(Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeDetailsScreen(anime: anime),
      ),
    );
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        _buildAppBar(),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spotlight shimmer
              Shimmer.fromColors(
                baseColor: AppColors.surface,
                highlightColor: AppColors.backgroundSecondary,
                child: Container(
                  height: 240,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              // Section shimmers
              for (int i = 0; i < 3; i++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                  child: Shimmer.fromColors(
                    baseColor: AppColors.surface,
                    highlightColor: AppColors.backgroundSecondary,
                    child: Container(
                      height: 24,
                      width: 150,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
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
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 12,
                                width: 80,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
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
