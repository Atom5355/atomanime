import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../services/download_cache_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/focusable_widget.dart';
import 'video_player_screen.dart';

/// Downloads screen - fully accessible on PC (mouse/keyboard), Android (touch), and TV (D-Pad)
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadCacheService _cacheService = DownloadCacheService();
  final ProfileService _profileService = ProfileService();
  
  List<DownloadedAnime> _downloadedAnime = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  final Set<String> _selectedEpisodes = {};
  String _filterCategory = 'all';
  int _totalSize = 0;
  
  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }
  
  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    final downloads = await _cacheService.getAllDownloadedAnime();
    final size = await _cacheService.getTotalDownloadSize();
    setState(() {
      _downloadedAnime = downloads;
      _totalSize = size;
      _isLoading = false;
    });
  }
  
  String _formatSize(int bytes) {
    if (bytes > 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
  }
  
  void _toggleSelection(CachedEpisode episode) {
    final key = '${episode.animeId}_${episode.episodeNumber}_${episode.category}';
    setState(() {
      if (_selectedEpisodes.contains(key)) {
        _selectedEpisodes.remove(key);
        if (_selectedEpisodes.isEmpty) _isSelectionMode = false;
      } else {
        _selectedEpisodes.add(key);
      }
    });
  }
  
  void _selectAll() {
    setState(() {
      _selectedEpisodes.clear();
      for (final anime in _downloadedAnime) {
        for (final ep in anime.episodes) {
          if (_filterCategory == 'all' || ep.category == _filterCategory) {
            _selectedEpisodes.add('${ep.animeId}_${ep.episodeNumber}_${ep.category}');
          }
        }
      }
    });
  }
  
  void _clearSelection() {
    setState(() {
      _selectedEpisodes.clear();
      _isSelectionMode = false;
    });
  }
  
  Future<void> _deleteSelected() async {
    if (_selectedEpisodes.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.glassBorder)),
        title: const Text('Delete Downloads', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete ${_selectedEpisodes.length} episode(s)? This cannot be undone.', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          UniversalButton(label: 'Cancel', isPrimary: false, onPressed: () => Navigator.pop(context, false)),
          UniversalButton(label: 'Delete', color: AppColors.error, textColor: Colors.white, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final toDelete = <CachedEpisode>[];
    for (final anime in _downloadedAnime) {
      for (final ep in anime.episodes) {
        final key = '${ep.animeId}_${ep.episodeNumber}_${ep.category}';
        if (_selectedEpisodes.contains(key)) toDelete.add(ep);
      }
    }
    
    final deleted = await _cacheService.deleteEpisodes(toDelete);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $deleted episode(s)'), backgroundColor: Colors.green[700]));
    }
    _clearSelection();
    _loadDownloads();
  }
  
  Future<void> _deleteAnime(DownloadedAnime anime) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.glassBorder)),
        title: const Text('Delete Anime', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete all ${anime.episodes.length} episode(s) of "${anime.title}"?', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          UniversalButton(label: 'Cancel', isPrimary: false, onPressed: () => Navigator.pop(context, false)),
          UniversalButton(label: 'Delete All', color: AppColors.error, textColor: Colors.white, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    
    if (confirmed != true) return;
    await _cacheService.deleteAnime(anime.animeId, anime.title);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "${anime.title}"'), backgroundColor: Colors.green[700]));
    }
    _loadDownloads();
  }
  
  void _playEpisode(CachedEpisode episode) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => VideoPlayerScreen(
        episodeId: '${episode.animeId}?ep=${episode.episodeNumber}',
        episodeTitle: 'Episode ${episode.episodeNumber}',
        episodeNumber: episode.episodeNumber,
        localFilePath: episode.filePath,
      ),
    ));
  }

  void _showFilterMenu() async {
    final result = await FocusableMenu.show<String>(
      context: context,
      header: Row(
        children: [
          Icon(Icons.filter_list, color: AppColors.neonYellow, size: 20),
          const SizedBox(width: 8),
          const Text('Filter', style: TextStyle(color: AppColors.neonYellow, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
      items: [
        FocusableMenuEntry(label: 'All${_filterCategory == 'all' ? ' ✓' : ''}', icon: Icons.all_inclusive, value: 'all'),
        FocusableMenuEntry(label: 'Sub Only${_filterCategory == 'sub' ? ' ✓' : ''}', icon: Icons.subtitles, value: 'sub'),
        FocusableMenuEntry(label: 'Dub Only${_filterCategory == 'dub' ? ' ✓' : ''}', icon: Icons.record_voice_over, value: 'dub'),
      ],
    );
    if (result != null) setState(() => _filterCategory = result);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: AppColors.background.withValues(alpha: 0.8)),
          ),
        ),
        title: _isSelectionMode
          ? NeonText('${_selectedEpisodes.length} selected', fontSize: 18)
          : const NeonText('Downloads', fontSize: 20, fontWeight: FontWeight.bold),
        leading: FocusableWidget(
          onSelect: () {
            if (_isSelectionMode) { _clearSelection(); } else { Navigator.pop(context); }
          },
          builder: (context, isFocused, isHovered) {
            return Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isFocused ? AppColors.neonYellow : AppColors.glass,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isFocused ? AppColors.neonYellow : AppColors.glassBorder),
              ),
              child: Icon(
                _isSelectionMode ? Icons.close : Icons.arrow_back,
                color: isFocused ? AppColors.background : AppColors.textPrimary,
              ),
            );
          },
        ),
        actions: [
          if (_isSelectionMode) ...[
            FocusableWidget(
              onSelect: _selectAll,
              builder: (context, isFocused, isHovered) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.select_all, color: isFocused ? AppColors.neonYellow : AppColors.textSecondary),
                );
              },
            ),
            FocusableWidget(
              onSelect: _deleteSelected,
              builder: (context, isFocused, isHovered) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.delete, color: isFocused ? AppColors.error : AppColors.error.withValues(alpha: 0.7)),
                );
              },
            ),
          ] else ...[
            FocusableWidget(
              onSelect: _showFilterMenu,
              builder: (context, isFocused, isHovered) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.filter_list, color: isFocused ? AppColors.neonYellow : AppColors.textSecondary),
                );
              },
            ),
            FocusableWidget(
              onSelect: _loadDownloads,
              builder: (context, isFocused, isHovered) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.refresh, color: isFocused ? AppColors.neonYellow : AppColors.textSecondary),
                );
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedGradientBackground(
        child: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.neonYellow))
          : _downloadedAnime.isEmpty
            ? _buildEmptyState()
            : _buildDownloadsList(),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_done, size: 80, color: AppColors.textMuted),
            const SizedBox(height: 20),
            const Text('No Downloads', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Downloaded episodes will appear here', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDownloadsList() {
    final profileName = _profileService.currentProfile?.name ?? 'Default';
    
    return Column(
      children: [
        // Storage info bar
        ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.glass,
                border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.neonYellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.person, color: AppColors.neonYellow, size: 16)),
                      const SizedBox(width: 10),
                      Text(profileName, style: const TextStyle(color: AppColors.neonYellow, fontWeight: FontWeight.w600, fontSize: 14)),
                      Text("'s Downloads", style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.storage, color: AppColors.textMuted, size: 18),
                      const SizedBox(width: 8),
                      NeonText('Total: ${_formatSize(_totalSize)}', fontSize: 14, fontWeight: FontWeight.bold, glowIntensity: 0.3),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.glassBorder)),
                        child: Text('${_downloadedAnime.length} anime \u2022 ${_downloadedAnime.fold<int>(0, (sum, a) => sum + a.episodes.length)} eps',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Anime list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _downloadedAnime.length,
            itemBuilder: (context, index) => _buildAnimeCard(_downloadedAnime[index]),
          ),
        ),
      ],
    );
  }
  
  Widget _buildAnimeCard(DownloadedAnime anime) {
    final filteredEpisodes = _filterCategory == 'all'
      ? anime.episodes
      : anime.episodes.where((e) => e.category == _filterCategory).toList();
    
    if (filteredEpisodes.isEmpty) return const SizedBox.shrink();
    
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      borderRadius: 16,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: anime.coverImage != null
              ? CachedNetworkImage(imageUrl: anime.coverImage!, width: 55, height: 75, fit: BoxFit.cover,
                  placeholder: (context, url) => Container(width: 55, height: 75, color: AppColors.surface),
                  errorWidget: (context, url, error) => Container(width: 55, height: 75, color: AppColors.surface, child: Icon(Icons.movie, color: AppColors.textMuted)))
              : Container(width: 55, height: 75, color: AppColors.surface, child: Icon(Icons.movie, color: AppColors.textMuted)),
          ),
          title: Text(anime.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text('${filteredEpisodes.length} ep${filteredEpisodes.length > 1 ? 's' : ''}', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.neonYellow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3))),
                  child: Text(anime.totalSizeFormatted, style: TextStyle(color: AppColors.neonYellow, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (anime.subEpisodes.isNotEmpty)
                  CategoryChip(label: 'SUB', count: anime.subEpisodes.length, isSub: true),
                if (anime.subEpisodes.isNotEmpty && anime.dubEpisodes.isNotEmpty)
                  const SizedBox(width: 6),
                if (anime.dubEpisodes.isNotEmpty)
                  CategoryChip(label: 'DUB', count: anime.dubEpisodes.length, isSub: false),
              ],
            ),
          ),
          trailing: FocusableWidget(
            onSelect: () => _deleteAnime(anime),
            builder: (context, isFocused, isHovered) {
              return Icon(Icons.delete_outline, color: isFocused ? AppColors.error : AppColors.textMuted, size: 22);
            },
          ),
          iconColor: AppColors.textMuted,
          collapsedIconColor: AppColors.textMuted,
          children: filteredEpisodes.map((ep) => _buildEpisodeTile(ep)).toList(),
        ),
      ),
    );
  }
  
  Widget _buildEpisodeTile(CachedEpisode episode) {
    final key = '${episode.animeId}_${episode.episodeNumber}_${episode.category}';
    final isSelected = _selectedEpisodes.contains(key);
    
    return FocusableWidget(
      onSelect: _isSelectionMode ? () => _toggleSelection(episode) : () => _playEpisode(episode),
      onLongPress: () {
        if (!_isSelectionMode) setState(() => _isSelectionMode = true);
        _toggleSelection(episode);
      },
      builder: (context, isFocused, isHovered) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.neonYellow.withValues(alpha: 0.15) : (isFocused ? AppColors.surface : AppColors.glass),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFocused ? AppColors.neonYellow : (isSelected ? AppColors.neonYellow.withValues(alpha: 0.5) : AppColors.glassBorder),
              width: isFocused ? 2 : 1,
            ),
            boxShadow: isFocused ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.3), blurRadius: 12)] : null,
          ),
          child: Row(
            children: [
              if (_isSelectionMode)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.neonYellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: isSelected ? AppColors.neonYellow : AppColors.glassBorder, width: 1.5),
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 16, color: AppColors.background) : null,
                ),
              // Episode number badge
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: episode.category == 'sub' ? [AppColors.sub, AppColors.sub.withValues(alpha: 0.7)] : [AppColors.dub, AppColors.dub.withValues(alpha: 0.7)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: (episode.category == 'sub' ? AppColors.sub : AppColors.dub).withValues(alpha: 0.3), blurRadius: 8)],
                ),
                child: Center(child: Text('${episode.episodeNumber}', style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 16))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Episode ${episode.episodeNumber}', style: TextStyle(color: isFocused ? AppColors.neonYellow : AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CategoryChip(label: episode.category.toUpperCase(), isSub: episode.category == 'sub'),
                        const SizedBox(width: 10),
                        Text(episode.fileSizeFormatted, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isSelectionMode)
                Icon(Icons.play_circle_filled, color: isFocused ? AppColors.neonYellow : AppColors.textMuted, size: 36),
            ],
          ),
        );
      },
    );
  }
}
