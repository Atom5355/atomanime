import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../services/download_cache_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'video_player_screen.dart';

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
  final Set<String> _selectedEpisodes = {}; // Using "animeId_ep_category" as key
  String _filterCategory = 'all'; // 'all', 'sub', 'dub'
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
        if (_selectedEpisodes.isEmpty) {
          _isSelectionMode = false;
        }
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
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Downloads', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete ${_selectedEpisodes.length} episode(s)? This cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Find episodes to delete
    final toDelete = <CachedEpisode>[];
    for (final anime in _downloadedAnime) {
      for (final ep in anime.episodes) {
        final key = '${ep.animeId}_${ep.episodeNumber}_${ep.category}';
        if (_selectedEpisodes.contains(key)) {
          toDelete.add(ep);
        }
      }
    }
    
    final deleted = await _cacheService.deleteEpisodes(toDelete);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $deleted episode(s)'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
    
    _clearSelection();
    _loadDownloads();
  }
  
  Future<void> _deleteAnime(DownloadedAnime anime) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Anime', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete all ${anime.episodes.length} episode(s) of "${anime.title}"?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    await _cacheService.deleteAnime(anime.animeId, anime.title);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${anime.title}"'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
    
    _loadDownloads();
  }
  
  void _playEpisode(CachedEpisode episode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          episodeId: '${episode.animeId}?ep=${episode.episodeNumber}',
          episodeTitle: 'Episode ${episode.episodeNumber}',
          episodeNumber: episode.episodeNumber,
          localFilePath: episode.filePath,
        ),
      ),
    );
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
            child: Container(
              color: AppColors.background.withValues(alpha: 0.8),
            ),
          ),
        ),
        title: _isSelectionMode
          ? NeonText('${_selectedEpisodes.length} selected', fontSize: 18)
          : const NeonText('Downloads', fontSize: 20, fontWeight: FontWeight.bold),
        leading: _isSelectionMode
          ? IconButton(
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: _clearSelection,
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
              onPressed: () => Navigator.pop(context),
            ),
        actions: [
          if (_isSelectionMode) ...[
            NeonIconButton(
              icon: Icons.select_all,
              onPressed: _selectAll,
              tooltip: 'Select All',
            ),
            NeonIconButton(
              icon: Icons.delete,
              onPressed: _deleteSelected,
              tooltip: 'Delete Selected',
              color: AppColors.error,
            ),
          ] else ...[
            // Filter dropdown
            PopupMenuButton<String>(
              icon: Icon(Icons.filter_list, color: AppColors.textSecondary),
              color: AppColors.backgroundSecondary,
              onSelected: (value) => setState(() => _filterCategory = value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      if (_filterCategory == 'all')
                        Icon(Icons.check, size: 16, color: AppColors.neonYellow),
                      const SizedBox(width: 8),
                      const Text('All', style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sub',
                  child: Row(
                    children: [
                      if (_filterCategory == 'sub')
                        Icon(Icons.check, size: 16, color: AppColors.neonYellow),
                      const SizedBox(width: 8),
                      const Text('Sub Only', style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'dub',
                  child: Row(
                    children: [
                      if (_filterCategory == 'dub')
                        Icon(Icons.check, size: 16, color: AppColors.neonYellow),
                      const SizedBox(width: 8),
                      const Text('Dub Only', style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
            NeonIconButton(
              icon: Icons.refresh,
              onPressed: _loadDownloads,
              tooltip: 'Refresh',
            ),
          ],
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
            const Text(
              'No Downloads',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloaded episodes will appear here',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDownloadsList() {
    final profileName = _profileService.currentProfile?.name ?? 'Default';
    
    return Column(
      children: [
        // Profile and storage info bar with glassmorphism
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
                  // Profile indicator
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.neonYellow.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.person, color: AppColors.neonYellow, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        profileName,
                        style: const TextStyle(color: AppColors.neonYellow, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        "'s Downloads",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Storage stats
                  Row(
                    children: [
                      Icon(Icons.storage, color: AppColors.textMuted, size: 18),
                      const SizedBox(width: 8),
                      NeonText(
                        'Total: ${_formatSize(_totalSize)}',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        glowIntensity: 0.3,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          '${_downloadedAnime.length} anime \u2022 ${_downloadedAnime.fold<int>(0, (sum, a) => sum + a.episodes.length)} eps',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
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
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: anime.coverImage != null
            ? CachedNetworkImage(
                imageUrl: anime.coverImage!,
                width: 55,
                height: 75,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 55,
                  height: 75,
                  color: AppColors.surface,
                ),
                errorWidget: (context, url, error) => Container(
                  width: 55,
                  height: 75,
                  color: AppColors.surface,
                  child: Icon(Icons.movie, color: AppColors.textMuted),
                ),
              )
            : Container(
                width: 55,
                height: 75,
                color: AppColors.surface,
                child: Icon(Icons.movie, color: AppColors.textMuted),
              ),
        ),
        title: Text(
          anime.title,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Text(
                '${filteredEpisodes.length} ep${filteredEpisodes.length > 1 ? 's' : ''}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.neonYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
                ),
                child: Text(
                  anime.totalSizeFormatted,
                  style: TextStyle(color: AppColors.neonYellow, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (anime.subEpisodes.isNotEmpty)
                CategoryChip(
                  label: 'SUB',
                  count: anime.subEpisodes.length,
                  isSub: true,
                ),
              if (anime.subEpisodes.isNotEmpty && anime.dubEpisodes.isNotEmpty)
                const SizedBox(width: 6),
              if (anime.dubEpisodes.isNotEmpty)
                CategoryChip(
                  label: 'DUB',
                  count: anime.dubEpisodes.length,
                  isSub: false,
                ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.grey),
          color: const Color(0xFF252525),
          onSelected: (value) {
            if (value == 'delete') {
              _deleteAnime(anime);
            } else if (value == 'select') {
              setState(() {
                _isSelectionMode = true;
                for (final ep in filteredEpisodes) {
                  _selectedEpisodes.add('${ep.animeId}_${ep.episodeNumber}_${ep.category}');
                }
              });
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'select',
              child: Row(
                children: [
                  Icon(Icons.check_box, size: 16, color: AppColors.neonYellow),
                  const SizedBox(width: 8),
                  const Text('Select All Episodes', style: TextStyle(color: AppColors.textPrimary)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text('Delete All', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
        iconColor: AppColors.textMuted,
        collapsedIconColor: AppColors.textMuted,
        children: filteredEpisodes.map((ep) => _buildEpisodeTile(ep)).toList(),
      ),
    );
  }
  
  Widget _buildEpisodeTile(CachedEpisode episode) {
    final key = '${episode.animeId}_${episode.episodeNumber}_${episode.category}';
    final isSelected = _selectedEpisodes.contains(key);
    
    return InkWell(
      onTap: _isSelectionMode 
        ? () => _toggleSelection(episode)
        : () => _playEpisode(episode),
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() => _isSelectionMode = true);
        }
        _toggleSelection(episode);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.neonYellow.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: AppColors.neonYellow.withValues(alpha: 0.5)) : Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            if (_isSelectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(episode),
                activeColor: AppColors.neonYellow,
                checkColor: AppColors.background,
              ),
            
            // Episode number
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: episode.category == 'sub' 
                    ? [AppColors.sub, AppColors.sub.withValues(alpha: 0.7)]
                    : [AppColors.dub, AppColors.dub.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: (episode.category == 'sub' ? AppColors.sub : AppColors.dub).withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${episode.episodeNumber}',
                  style: const TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            
            // Episode info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Episode ${episode.episodeNumber}',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      CategoryChip(
                        label: episode.category.toUpperCase(),
                        isSub: episode.category == 'sub',
                      ),
                      const SizedBox(width: 10),
                      Text(
                        episode.fileSizeFormatted,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Play button
            if (!_isSelectionMode)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.play_circle_filled, color: AppColors.neonYellow, size: 36),
                  onPressed: () => _playEpisode(episode),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
