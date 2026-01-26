import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../services/aniwatch_service.dart';

class AnimeProvider with ChangeNotifier {
  final AniwatchService _aniwatchService = AniwatchService();

  // Home page sections
  Map<String, List<Anime>> _homeData = {};
  List<Anime> _searchResults = [];
  List<Episode> _episodes = [];
  Anime? _currentAnimeDetails;
  
  // Cache of spotlight banners by anime ID for quick lookup
  final Map<String, String> _spotlightBanners = {};
  
  bool _isLoadingHome = false;
  bool _isSearching = false;
  bool _isLoadingEpisodes = false;
  bool _isLoadingDetails = false;

  // Getters for home sections
  List<Anime> get spotlight => _homeData['spotlight'] ?? [];
  List<Anime> get trending => _homeData['trending'] ?? [];
  List<Anime> get latest => _homeData['latest'] ?? [];
  List<Anime> get topAiring => _homeData['topAiring'] ?? [];
  List<Anime> get popular => _homeData['popular'] ?? [];
  List<Anime> get favorite => _homeData['favorite'] ?? [];
  List<Anime> get top10Today => _homeData['top10Today'] ?? [];
  List<Anime> get completed => _homeData['completed'] ?? [];
  
  List<Anime> get searchResults => _searchResults;
  List<Episode> get episodes => _episodes;
  Anime? get currentAnimeDetails => _currentAnimeDetails;
  
  bool get isLoadingHome => _isLoadingHome;
  bool get isSearching => _isSearching;
  bool get isLoadingEpisodes => _isLoadingEpisodes;
  bool get isLoadingDetails => _isLoadingDetails;
  
  /// Get the spotlight banner for an anime if available
  /// Returns the 1366x768 promotional image if the anime was in spotlight
  String? getSpotlightBanner(String animeId) => _spotlightBanners[animeId];

  // Load home page data
  Future<void> loadHomePage() async {
    _isLoadingHome = true;
    notifyListeners();

    _homeData = await _aniwatchService.getHomePage();
    
    // Cache spotlight banners for quick lookup
    for (final anime in spotlight) {
      if (anime.coverImage != null && anime.coverImage!.contains('1366x768')) {
        _spotlightBanners[anime.id] = anime.coverImage!;
      }
    }
    
    _isLoadingHome = false;
    notifyListeners();
  }

  // Search anime
  Future<void> searchAnime(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    _searchResults = await _aniwatchService.searchAnime(query);
    
    _isSearching = false;
    notifyListeners();
  }

  // Load anime details
  Future<void> loadAnimeDetails(String animeId) async {
    _isLoadingDetails = true;
    _currentAnimeDetails = null;
    notifyListeners();

    _currentAnimeDetails = await _aniwatchService.getAnimeInfo(animeId);
    
    _isLoadingDetails = false;
    notifyListeners();
  }

  // Load episodes by anime ID
  Future<void> loadEpisodes(String animeId) async {
    _isLoadingEpisodes = true;
    _episodes = [];
    notifyListeners();

    debugPrint('Loading episodes for: $animeId');
    _episodes = await _aniwatchService.getEpisodes(animeId);
    debugPrint('Loaded ${_episodes.length} episodes');

    _isLoadingEpisodes = false;
    notifyListeners();
  }

  Future<StreamingData?> getStreamingData(String episodeId, {String category = 'sub'}) async {
    return await _aniwatchService.getStreamingSources(episodeId, category: category);
  }

  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }
}
