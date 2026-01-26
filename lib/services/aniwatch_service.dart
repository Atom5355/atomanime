import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/anime.dart';
import '../models/episode.dart';

class AniwatchService {
  // Production backend on VPS
  static const String _baseUrl = 'http://193.31.31.96:3001/api';

  // Get home page data (trending, latest, popular, etc.)
  Future<Map<String, List<Anime>>> getHomePage() async {
    try {
      final url = '$_baseUrl/home';
      debugPrint('Fetching home page from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          final homeData = data['data'];
          Map<String, List<Anime>> result = {};
          
          // Parse spotlightAnimes
          if (homeData['spotlightAnimes'] != null) {
            result['spotlight'] = _parseAnimeList(homeData['spotlightAnimes']);
          }
          
          // Parse trendingAnimes
          if (homeData['trendingAnimes'] != null) {
            result['trending'] = _parseAnimeList(homeData['trendingAnimes']);
          }
          
          // Parse latestEpisodeAnimes
          if (homeData['latestEpisodeAnimes'] != null) {
            result['latest'] = _parseAnimeList(homeData['latestEpisodeAnimes']);
          }
          
          // Parse topUpcomingAnimes
          if (homeData['topUpcomingAnimes'] != null) {
            result['upcoming'] = _parseAnimeList(homeData['topUpcomingAnimes']);
          }
          
          // Parse top10Animes
          if (homeData['top10Animes'] != null) {
            if (homeData['top10Animes']['today'] != null) {
              result['top10Today'] = _parseAnimeList(homeData['top10Animes']['today']);
            }
            if (homeData['top10Animes']['week'] != null) {
              result['top10Week'] = _parseAnimeList(homeData['top10Animes']['week']);
            }
            if (homeData['top10Animes']['month'] != null) {
              result['top10Month'] = _parseAnimeList(homeData['top10Animes']['month']);
            }
          }
          
          // Parse topAiringAnimes
          if (homeData['topAiringAnimes'] != null) {
            result['topAiring'] = _parseAnimeList(homeData['topAiringAnimes']);
          }
          
          // Parse mostPopularAnimes
          if (homeData['mostPopularAnimes'] != null) {
            result['popular'] = _parseAnimeList(homeData['mostPopularAnimes']);
          }
          
          // Parse mostFavoriteAnimes
          if (homeData['mostFavoriteAnimes'] != null) {
            result['favorite'] = _parseAnimeList(homeData['mostFavoriteAnimes']);
          }
          
          // Parse latestCompletedAnimes
          if (homeData['latestCompletedAnimes'] != null) {
            result['completed'] = _parseAnimeList(homeData['latestCompletedAnimes']);
          }
          
          debugPrint('Loaded home page sections: ${result.keys.join(', ')}');
          return result;
        }
      }
      return {};
    } catch (e) {
      debugPrint('Error getting home page: $e');
      return {};
    }
  }

  List<Anime> _parseAnimeList(List<dynamic> list) {
    return list.map((item) => Anime.fromHiAnimeJson(item)).toList();
  }

  // Get anime info by ID
  Future<Anime?> getAnimeInfo(String animeId) async {
    try {
      final url = '$_baseUrl/anime/$animeId';
      debugPrint('Fetching anime info: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          return Anime.fromHiAnimeDetailsJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting anime info: $e');
      return null;
    }
  }

  // Search anime
  Future<List<Anime>> searchAnime(String query, {int page = 1}) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = '$_baseUrl/search?q=$encodedQuery&page=$page';
      debugPrint('Searching anime: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          final animes = data['data']['animes'] as List<dynamic>?;
          if (animes != null) {
            return animes.map((item) => Anime.fromHiAnimeJson(item)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error searching anime: $e');
      return [];
    }
  }

  // Get anime episodes
  Future<List<Episode>> getEpisodes(String animeId) async {
    try {
      final url = '$_baseUrl/anime/$animeId/episodes';
      debugPrint('Fetching episodes: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          // The API returns { totalEpisodes: X, episodes: [...] }
          // All episodes are in one flat list (both sub and dub mixed)
          // Category is determined when fetching streaming sources, not here
          final episodes = data['data']['episodes'] as List<dynamic>?;
          if (episodes != null) {
            debugPrint('Loaded ${episodes.length} total episodes');
            return episodes.map((ep) => Episode(
              id: ep['episodeId']?.toString() ?? '',
              number: ep['number'] ?? 1,
              title: ep['title']?.toString() ?? 'Episode ${ep['number'] ?? 1}',
              thumbnail: null,
              isFiller: ep['isFiller'] == true,
              category: null, // Category determined at playback time
            )).toList();
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting episodes: $e');
      return [];
    }
  }

  // Get episode streaming sources with full data
  // Retries indefinitely until server returns sources or explicit failure
  Future<StreamingData?> getStreamingSources(String episodeId, {String server = 'hd-1', String category = 'sub'}) async {
    int retryCount = 0;
    const maxRetries = 10; // Will retry up to 10 times (covering ~2+ minutes of waiting)
    
    while (retryCount < maxRetries) {
      try {
        // URL encode the episode ID since it may contain ?ep=
        final encodedEpisodeId = Uri.encodeComponent(episodeId);
        final url = '$_baseUrl/episode/$encodedEpisodeId/sources?server=$server&category=$category';
        debugPrint('Fetching streaming sources (attempt ${retryCount + 1}): $url');

        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 30)); // 30 second timeout per attempt

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['success'] == true && data['data'] != null) {
            final streamingData = StreamingData.fromJson(data['data']);
            if (streamingData.sources.isNotEmpty) {
              debugPrint('Found ${streamingData.sources.length} sources, ${streamingData.subtitles.length} subtitles');
              return streamingData;
            }
          }
          
          // Server responded but no sources - this is an explicit "not found"
          if (data['success'] == false || (data['data'] != null && data['data']['sources'] != null && (data['data']['sources'] as List).isEmpty)) {
            debugPrint('Server explicitly returned no sources');
            return null;
          }
        } else if (response.statusCode >= 500) {
          // Server error - retry
          debugPrint('Server error ${response.statusCode}, retrying...');
        } else if (response.statusCode == 404) {
          // Not found - explicit failure
          debugPrint('Episode not found (404)');
          return null;
        }
        
        // Retry with exponential backoff
        retryCount++;
        if (retryCount < maxRetries) {
          final delay = Duration(seconds: 2 + (retryCount * 2)); // 4s, 6s, 8s, 10s, ...
          debugPrint('Retrying in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        }
      } catch (e) {
        debugPrint('Error getting streaming sources (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          // Wait before retry on network errors
          final delay = Duration(seconds: 2 + (retryCount * 2));
          debugPrint('Retrying in ${delay.inSeconds} seconds after error...');
          await Future.delayed(delay);
        }
      }
    }
    
    debugPrint('Max retries exceeded for streaming sources');
    return null;
  }

  // Get episode servers
  Future<List<Map<String, dynamic>>> getEpisodeServers(String episodeId) async {
    try {
      final url = '$_baseUrl/episode/$episodeId/servers';
      debugPrint('Fetching episode servers: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          List<Map<String, dynamic>> servers = [];
          
          // Sub servers
          final subServers = data['data']['sub'] as List<dynamic>?;
          if (subServers != null) {
            for (var server in subServers) {
              servers.add({
                'name': server['serverName']?.toString() ?? 'Unknown',
                'type': 'sub',
              });
            }
          }
          
          // Dub servers
          final dubServers = data['data']['dub'] as List<dynamic>?;
          if (dubServers != null) {
            for (var server in dubServers) {
              servers.add({
                'name': server['serverName']?.toString() ?? 'Unknown',
                'type': 'dub',
              });
            }
          }
          
          return servers;
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting episode servers: $e');
      return [];
    }
  }

  // Get anime by category
  Future<List<Anime>> getCategoryAnime(String category, {int page = 1}) async {
    try {
      final url = '$_baseUrl/category/$category?page=$page';
      debugPrint('Fetching category: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          final animes = data['data']['animes'] as List<dynamic>?;
          if (animes != null) {
            return animes.map((item) => Anime.fromHiAnimeJson(item)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting category anime: $e');
      return [];
    }
  }
}
