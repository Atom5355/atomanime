import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../models/anime.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;
import 'anime_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  void _performSearch() {
    if (_searchController.text.isNotEmpty) {
      Provider.of<AnimeProvider>(context, listen: false)
          .searchAnime(_searchController.text);
    }
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
    
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: AppColors.glass,
            ),
          ),
        ),
        leading: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                Navigator.pop(context);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final isFocused = Focus.of(context).hasFocus;
              return GlassCard(
                margin: const EdgeInsets.all(8),
                padding: EdgeInsets.zero,
                borderRadius: 10,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: isFocused
                        ? Border.all(color: AppColors.neonYellow, width: 2)
                        : null,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              );
            },
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16 * tvScale),
                cursorColor: AppColors.neonYellow,
                decoration: InputDecoration(
                  hintText: 'Search anime...',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16 * tvScale),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _performSearch(),
                onChanged: (value) {
                  // Auto-search with debounce for Fire TV (no Enter key)
                  _searchDebounce?.cancel();
                  if (value.length >= 3) {
                    _searchDebounce = Timer(const Duration(milliseconds: 800), () {
                      if (value.isNotEmpty && mounted) {
                        _performSearch();
                      }
                    });
                  }
                },
              ),
            ),
            // Search button for D-Pad users
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    _performSearch();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final isFocused = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: _performSearch,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 * tvScale,
                        vertical: 8 * tvScale,
                      ),
                      margin: EdgeInsets.only(left: 8 * tvScale),
                      decoration: BoxDecoration(
                        color: isFocused ? AppColors.neonYellow : AppColors.glass,
                        borderRadius: BorderRadius.circular(8 * tvScale),
                        border: Border.all(
                          color: isFocused ? AppColors.neonYellow : AppColors.glassBorder,
                          width: isFocused ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search,
                            color: isFocused ? AppColors.background : AppColors.textPrimary,
                            size: 18 * tvScale,
                          ),
                          SizedBox(width: 4 * tvScale),
                          Text(
                            'SEARCH',
                            style: TextStyle(
                              color: isFocused ? AppColors.background : AppColors.textPrimary,
                              fontSize: 12 * tvScale,
                              fontWeight: FontWeight.bold,
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
        ),
        actions: [
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  _searchController.clear();
                  Provider.of<AnimeProvider>(context, listen: false).clearSearch();
                  _searchFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return Container(
                  decoration: isFocused
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.neonYellow, width: 2),
                        )
                      : null,
                  child: NeonIconButton(
                    icon: Icons.clear,
                    onPressed: () {
                      _searchController.clear();
                      Provider.of<AnimeProvider>(context, listen: false).clearSearch();
                      _searchFocusNode.requestFocus();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Consumer<AnimeProvider>(
              builder: (context, provider, child) {
                final tvScale = TvScale.factor(context);
                
                if (provider.isSearching) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.neonYellow),
                  );
                }

                if (provider.searchResults.isEmpty) {
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
                          'Type and press SEARCH button',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 16 * tvScale),
                        ),
                        SizedBox(height: 8 * tvScale),
                        Text(
                          'Use D-Pad to navigate results',
                          style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6), fontSize: 12 * tvScale),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.all(16 * tvScale),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: TvScale.isTvMode(context) ? 4 : 2,
                    childAspectRatio: 0.55,
                    crossAxisSpacing: 14 * tvScale,
                    mainAxisSpacing: 14 * tvScale,
                  ),
                  itemCount: provider.searchResults.length,
                  itemBuilder: (context, index) {
                    return _buildSearchResultCard(provider.searchResults[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultCard(Anime anime) {
    final tvScale = TvScale.factor(context);
    
    void navigateToDetails() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AnimeDetailsScreen(anime: anime),
        ),
      );
    }
    
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle Select/Enter/Space for Fire TV remote
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            navigateToDetails();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: navigateToDetails,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * tvScale),
                border: Border.all(
                  color: isFocused ? AppColors.neonYellow : Colors.transparent,
                  width: isFocused ? 3 : 0,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.neonYellow.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14 * tvScale)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: anime.coverImage ?? '',
                              width: double.infinity,
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
                                child: const Icon(Icons.error, color: AppColors.textMuted),
                              ),
                            ),
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
                          ],
                        ),
                      ),
                    ),
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
                                gradient: LinearGradient(
                                  colors: [AppColors.neonYellow, AppColors.neonYellow.withValues(alpha: 0.7)],
                                ),
                                borderRadius: BorderRadius.circular(6 * tvScale),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star, size: 12 * tvScale, color: AppColors.background),
                                  SizedBox(width: 3 * tvScale),
                                  Text(
                                    (anime.averageScore! / 10).toStringAsFixed(1),
                                    style: TextStyle(
                                      color: AppColors.background,
                                      fontSize: 11 * tvScale,
                                      fontWeight: FontWeight.bold,
                                    ),
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
    );
  }
}
