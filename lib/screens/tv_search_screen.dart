import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../models/anime.dart';
import '../widgets/common_widgets.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;
import 'anime_details_screen.dart';

/// TV-optimized search screen with auto-search and grid layout
/// Designed for D-Pad/remote navigation on Android TV/Fire TV
class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  bool _showKeyboard = true;
  
  @override
  void initState() {
    super.initState();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  /// Auto-search with debounce - searches automatically as user types
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      Provider.of<AnimeProvider>(context, listen: false).clearSearch();
      return;
    }
    
    // 500ms debounce to avoid too many API calls while typing
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.length >= 2) {
        Provider.of<AnimeProvider>(context, listen: false).searchAnime(query);
      }
    });
  }
  
  void _performSearch() {
    if (_searchController.text.length >= 2) {
      _debounceTimer?.cancel();
      Provider.of<AnimeProvider>(context, listen: false).searchAnime(_searchController.text);
      // Hide keyboard focus to allow grid navigation
      setState(() => _showKeyboard = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final tvScale = TvScale.factor(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                // Search header
                _buildSearchHeader(tvScale),
                // Results grid
                Expanded(
                  child: _buildSearchResults(tvScale),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchHeader(double tvScale) {
    return Container(
      padding: EdgeInsets.all(20 * tvScale),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: AppColors.glassBorder.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button and title row
          Row(
            children: [
              // Back button - focusable for D-Pad
              Focus(
                autofocus: false,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                       event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.all(12 * tvScale),
                        decoration: BoxDecoration(
                          color: isFocused ? AppColors.neonYellow : AppColors.glass,
                          borderRadius: BorderRadius.circular(12 * tvScale),
                          border: Border.all(
                            color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                            width: isFocused ? 2 : 1,
                          ),
                          boxShadow: isFocused
                              ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.4), blurRadius: 15)]
                              : null,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: isFocused ? AppColors.background : AppColors.textPrimary,
                          size: 24 * tvScale,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: 16 * tvScale),
              Text(
                'Search Anime',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28 * tvScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 20 * tvScale),
          // Search input row
          Row(
            children: [
              // Search text field
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (hasFocus) setState(() => _showKeyboard = true);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20 * tvScale),
                    height: 56 * tvScale,
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(12 * tvScale),
                      border: Border.all(
                        color: _searchFocusNode.hasFocus
                            ? AppColors.neonYellow
                            : AppColors.glassBorder,
                        width: _searchFocusNode.hasFocus ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          color: AppColors.textSecondary,
                          size: 24 * tvScale,
                        ),
                        SizedBox(width: 12 * tvScale),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18 * tvScale,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type to search (auto-searches)...',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16 * tvScale,
                              ),
                              border: InputBorder.none,
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _performSearch(),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              Provider.of<AnimeProvider>(context, listen: false).clearSearch();
                            },
                            child: Icon(
                              Icons.close,
                              color: AppColors.textMuted,
                              size: 20 * tvScale,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12 * tvScale),
              // Clear/Search button for D-Pad users
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                       event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
                    _performSearch();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: _performSearch,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: 24 * tvScale,
                          vertical: 16 * tvScale,
                        ),
                        decoration: BoxDecoration(
                          color: isFocused ? AppColors.neonYellow : AppColors.glass,
                          borderRadius: BorderRadius.circular(12 * tvScale),
                          border: Border.all(
                            color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                            width: isFocused ? 2 : 1,
                          ),
                          boxShadow: isFocused
                              ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.4), blurRadius: 15)]
                              : null,
                        ),
                        child: Text(
                          'SEARCH',
                          style: TextStyle(
                            color: isFocused ? AppColors.background : AppColors.textPrimary,
                            fontSize: 14 * tvScale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * tvScale),
          Text(
            'Auto-searches as you type • Use D-Pad to navigate results',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12 * tvScale,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchResults(double tvScale) {
    return Consumer<AnimeProvider>(
      builder: (context, provider, child) {
        if (provider.isSearching) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.neonYellow),
                SizedBox(height: 20 * tvScale),
                Text(
                  'Searching...',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16 * tvScale),
                ),
              ],
            ),
          );
        }
        
        if (provider.searchResults.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _searchController.text.isEmpty ? Icons.search : Icons.search_off,
                  size: 80 * tvScale,
                  color: AppColors.neonYellow.withValues(alpha: 0.3),
                ),
                SizedBox(height: 20 * tvScale),
                Text(
                  _searchController.text.isEmpty
                      ? 'Start typing to search'
                      : 'No results found',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 18 * tvScale,
                  ),
                ),
                SizedBox(height: 8 * tvScale),
                Text(
                  'Search automatically starts after 2+ characters',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    fontSize: 14 * tvScale,
                  ),
                ),
              ],
            ),
          );
        }
        
        // Grid of results - optimized for TV with 5 columns
        final crossAxisCount = TvScale.isTvMode(context) ? 5 : 3;
        
        return GridView.builder(
          padding: EdgeInsets.all(20 * tvScale),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.55,
            crossAxisSpacing: 16 * tvScale,
            mainAxisSpacing: 16 * tvScale,
          ),
          itemCount: provider.searchResults.length,
          itemBuilder: (context, index) {
            return _buildResultCard(provider.searchResults[index], index, tvScale);
          },
        );
      },
    );
  }
  
  Widget _buildResultCard(Anime anime, int index, double tvScale) {
    return Focus(
      // Auto-focus first result when grid loads
      autofocus: index == 0 && !_showKeyboard,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AnimeDetailsScreen(anime: anime)),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AnimeDetailsScreen(anime: anime)),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: isFocused ? (Matrix4.identity()..scale(1.08)) : Matrix4.identity(),
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
                          width: isFocused ? 3 : 1.5,
                        ),
                        boxShadow: isFocused
                            ? [
                                BoxShadow(
                                  color: AppColors.neonYellow.withValues(alpha: 0.5),
                                  blurRadius: 25,
                                  spreadRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10 * tvScale),
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
                                child: Icon(Icons.movie, color: AppColors.textMuted, size: 40 * tvScale),
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
                                      AppColors.neonYellow.withValues(alpha: 0.3),
                                    ],
                                  ),
                                ),
                              ),
                            // Rating badge
                            if (anime.averageScore != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8 * tvScale, vertical: 4 * tvScale),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(6 * tvScale),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, color: AppColors.neonYellow, size: 12 * tvScale),
                                      SizedBox(width: 3),
                                      Text(
                                        (anime.averageScore! / 10).toStringAsFixed(1),
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 11 * tvScale,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Episode count badge
                            if (anime.subEpisodes != null || anime.dubEpisodes != null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8 * tvScale, vertical: 4 * tvScale),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(6 * tvScale),
                                  ),
                                  child: Text(
                                    'EP ${anime.subEpisodes ?? anime.dubEpisodes}',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 10 * tvScale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            // Play icon when focused
                            if (isFocused)
                              Center(
                                child: Container(
                                  padding: EdgeInsets.all(16 * tvScale),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonYellow,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neonYellow.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.play_arrow,
                                    color: AppColors.background,
                                    size: 28 * tvScale,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 10 * tvScale),
                  Text(
                    anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                      fontSize: 14 * tvScale,
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
}
