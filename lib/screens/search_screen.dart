import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../models/anime.dart';
import '../theme/app_theme.dart';
import '../widgets/focusable_widget.dart';
import '../main.dart' show TvScale;
import 'anime_details_screen.dart';

/// Full-screen search that works on PC (keyboard), Android (touch), and TV (D-Pad).
/// - Search field auto-focuses for immediate typing
/// - Dedicated Search button for D-Pad users (no auto-search on every character)
/// - Results displayed as a focusable grid with 2D D-Pad navigation
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_field');
  Timer? _searchDebounce;

  void _performSearch() {
    if (_searchController.text.isEmpty) return;
    _searchDebounce?.cancel();
    // Unfocus the text field so D-Pad can navigate results
    FocusScope.of(context).unfocus();
    Provider.of<AnimeProvider>(context, listen: false)
        .searchAnime(_searchController.text);
  }

  void _clearSearch() {
    _searchController.clear();
    Provider.of<AnimeProvider>(context, listen: false).clearSearch();
    _searchFocusNode.requestFocus();
  }

  void _navigateToDetails(Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeDetailsScreen(anime: anime),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvScale = TvScale.factor(context);
    final isTv = TvScale.isTvMode(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                // Search bar area
                _buildSearchBar(tvScale, isTv),
                // Results area
                Expanded(
                  child: Consumer<AnimeProvider>(
                    builder: (context, provider, child) {
                      if (provider.isSearching) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.neonYellow),
                              SizedBox(height: 16 * tvScale),
                              Text('Searching...', style: TextStyle(color: AppColors.textMuted, fontSize: 14 * tvScale)),
                            ],
                          ),
                        );
                      }

                      if (provider.searchResults.isEmpty) {
                        return _buildEmptyState(tvScale);
                      }

                      return _buildSearchResults(provider.searchResults, tvScale, isTv);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(double tvScale, bool isTv) {
    return Container(
      padding: EdgeInsets.all(12 * tvScale),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          // Back button - focusable
          FocusableWidget(
            onSelect: () => Navigator.pop(context),
            builder: (context, isFocused, isHovered) {
              return Container(
                padding: EdgeInsets.all(10 * tvScale),
                decoration: BoxDecoration(
                  color: isFocused ? AppColors.neonYellow : AppColors.glass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                    width: isFocused ? 2 : 1,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back,
                  color: isFocused ? AppColors.background : AppColors.textPrimary,
                  size: 20 * tvScale,
                ),
              );
            },
          ),
          SizedBox(width: 12 * tvScale),
          // Search text field
          Expanded(
            child: DpadFormField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              hintText: 'Search anime...',
              prefixIcon: Icons.search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              onChanged: (value) {
                // Debounced auto-search for PC/touch (not on every character for TV)
                _searchDebounce?.cancel();
                if (value.isNotEmpty) {
                  _searchDebounce = Timer(const Duration(milliseconds: 800), () {
                    if (value.isNotEmpty && mounted) {
                      _performSearch();
                    }
                  });
                }
              },
            ),
          ),
          SizedBox(width: 8 * tvScale),
          // Search button - critical for D-Pad/TV users
          UniversalButton(
            label: isTv ? 'GO' : 'Search',
            icon: Icons.search,
            onPressed: _performSearch,
            padding: EdgeInsets.symmetric(horizontal: 16 * tvScale, vertical: 12 * tvScale),
          ),
          SizedBox(width: 8 * tvScale),
          // Clear button
          FocusableWidget(
            onSelect: _clearSearch,
            builder: (context, isFocused, isHovered) {
              return Container(
                padding: EdgeInsets.all(10 * tvScale),
                decoration: BoxDecoration(
                  color: isFocused ? AppColors.error.withValues(alpha: 0.2) : AppColors.glass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isFocused ? AppColors.error : AppColors.glassBorder,
                    width: isFocused ? 2 : 1,
                  ),
                ),
                child: Icon(
                  Icons.clear,
                  color: isFocused ? AppColors.error : AppColors.textMuted,
                  size: 20 * tvScale,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double tvScale) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search,
            size: 64 * tvScale,
            color: AppColors.neonYellow.withValues(alpha: 0.3),
          ),
          SizedBox(height: 16 * tvScale),
          Text(
            'Search for anime',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18 * tvScale,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8 * tvScale),
          Text(
            'Type a name and press Search',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14 * tvScale),
          ),
          SizedBox(height: 4 * tvScale),
          Text(
            'Use D-Pad arrows to navigate results',
            style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6), fontSize: 12 * tvScale),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<Anime> results, double tvScale, bool isTv) {
    // Calculate grid columns based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = isTv ? 5 : (screenWidth > 800 ? 4 : (screenWidth > 500 ? 3 : 2));
    
    return FocusableGrid(
      itemCount: results.length,
      crossAxisCount: crossAxisCount,
      childAspectRatio: 0.55,
      crossAxisSpacing: 14 * tvScale,
      mainAxisSpacing: 14 * tvScale,
      padding: EdgeInsets.all(16 * tvScale),
      onItemSelect: (index) {
        if (index < results.length) {
          _navigateToDetails(results[index]);
        }
      },
      itemBuilder: (context, index, isFocused) {
        return _buildSearchResultCard(results[index], isFocused, tvScale);
      },
    );
  }

  Widget _buildSearchResultCard(Anime anime, bool isFocused, double tvScale) {
    return GestureDetector(
      onTap: () => _navigateToDetails(anime),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isFocused ? Matrix4.diagonal3Values(1.05, 1.05, 1) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14 * tvScale),
          border: Border.all(
            color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
            width: isFocused ? 3 : 1,
          ),
          boxShadow: isFocused
              ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13 * tvScale),
          child: Container(
            color: AppColors.glass,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster image
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: anime.coverImage ?? '',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: AppColors.surface,
                          child: Center(child: CircularProgressIndicator(color: AppColors.neonYellow, strokeWidth: 2)),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.error, color: AppColors.textMuted),
                        ),
                      ),
                      if (isFocused)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, AppColors.neonYellow.withValues(alpha: 0.3)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Info section
                Padding(
                  padding: EdgeInsets.all(10 * tvScale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                          fontSize: 13 * tvScale,
                          fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      if (anime.averageScore != null) ...[
                        SizedBox(height: 6 * tvScale),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * tvScale, vertical: 3 * tvScale),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.7)]),
                            borderRadius: BorderRadius.circular(6 * tvScale),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 12 * tvScale, color: AppColors.background),
                              SizedBox(width: 3 * tvScale),
                              Text(
                                (anime.averageScore! / 10).toStringAsFixed(1),
                                style: TextStyle(color: AppColors.background, fontSize: 11 * tvScale, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
