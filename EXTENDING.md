# Extending ATOM ANIME - Developer Gui
## 🎯 How to Add New Features

### 1. Add Favorites/Watchlist

**Step 1:** Create a favorites provider

```dart
// lib/providers/favorites_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';

class FavoritesProvider with ChangeNotifier {
  List<int> _favoriteIds = [];
  
  List<int> get favoriteIds => _favoriteIds;
  
  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteIds = prefs.getStringList('favorites')
        ?.map((e) => int.parse(e))
        .toList() ?? [];
    notifyListeners();
  }
  
  Future<void> toggleFavorite(int animeId) async {
    if (_favoriteIds.contains(animeId)) {
      _favoriteIds.remove(animeId);
    } else {
      _favoriteIds.add(animeId);
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'favorites',
      _favoriteIds.map((e) => e.toString()).toList(),
    );
    notifyListeners();
  }
  
  bool isFavorite(int animeId) => _favoriteIds.contains(animeId);
}
```

**Step 2:** Add to providers in main.dart

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AnimeProvider()),
    ChangeNotifierProvider(create: (_) => FavoritesProvider()),
  ],
  child: MaterialApp(...),
)
```

**Step 3:** Add favorite button in anime details

```dart
Consumer<FavoritesProvider>(
  builder: (context, favProvider, child) {
    final isFav = favProvider.isFavorite(widget.anime.id);
    return IconButton(
      icon: Icon(
        isFav ? Icons.favorite : Icons.favorite_border,
        color: isFav ? Colors.red : Colors.white,
      ),
      onPressed: () {
        favProvider.toggleFavorite(widget.anime.id);
      },
    );
  },
)
```

---

### 2. Add Continue Watching

**Step 1:** Create watch history model

```dart
// lib/models/watch_history.dart
class WatchHistory {
  final int animeId;
  final String animeTitle;
  final int episodeNumber;
  final int position; // in seconds
  final DateTime lastWatched;
  
  WatchHistory({
    required this.animeId,
    required this.animeTitle,
    required this.episodeNumber,
    required this.position,
    required this.lastWatched,
  });
  
  Map<String, dynamic> toJson() => {
    'animeId': animeId,
    'animeTitle': animeTitle,
    'episodeNumber': episodeNumber,
    'position': position,
    'lastWatched': lastWatched.toIso8601String(),
  };
  
  factory WatchHistory.fromJson(Map<String, dynamic> json) => WatchHistory(
    animeId: json['animeId'],
    animeTitle: json['animeTitle'],
    episodeNumber: json['episodeNumber'],
    position: json['position'],
    lastWatched: DateTime.parse(json['lastWatched']),
  );
}
```

**Step 2:** Update video player to save progress

```dart
@override
void dispose() {
  _saveWatchProgress();
  _videoPlayerController?.dispose();
  super.dispose();
}

Future<void> _saveWatchProgress() async {
  if (_videoPlayerController != null) {
    final position = _videoPlayerController!.value.position.inSeconds;
    final prefs = await SharedPreferences.getInstance();
    
    final history = WatchHistory(
      animeId: widget.animeId,
      animeTitle: widget.animeTitle,
      episodeNumber: widget.episodeNumber,
      position: position,
      lastWatched: DateTime.now(),
    );
    
    // Save to local storage
    await prefs.setString('watch_${widget.animeId}_${widget.episodeNumber}', 
                           jsonEncode(history.toJson()));
  }
}
```

---

### 3. Add Download Feature

**Step 1:** Add download manager

```dart
// lib/services/download_service.dart
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadService {
  final Dio _dio = Dio();
  
  Future<void> downloadEpisode(
    String url,
    String fileName,
    Function(int, int) onProgress,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';
      
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
      );
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }
}
```

**Step 2:** Add download button in episode list

```dart
IconButton(
  icon: const Icon(Icons.download),
  onPressed: () async {
    final links = await provider.getStreamingLinks(episode.id);
    if (links.isNotEmpty) {
      final downloadService = DownloadService();
      await downloadService.downloadEpisode(
        links.first.url,
        'episode_${episode.number}.mp4',
        (received, total) {
          print('Progress: ${(received / total * 100).toStringAsFixed(0)}%');
        },
      );
    }
  },
)
```

---

### 4. Add Multiple API Sources

**Step 1:** Create anime source interface

```dart
// lib/services/anime_source.dart
abstract class AnimeSource {
  Future<String?> getAnimeId(String title);
  Future<List<Episode>> getEpisodes(String animeId);
  Future<List<StreamingLink>> getStreamingLinks(String episodeId);
}
```

**Step 2:** Implement different sources

```dart
// lib/services/sources/zoro_source.dart
class ZoroSource implements AnimeSource {
  static const String _baseUrl = 'https://api.consumet.org/anime/zoro';
  
  @override
  Future<String?> getAnimeId(String title) async {
    // Implementation
  }
  
  // Implement other methods...
}
```

**Step 3:** Add source selector

```dart
enum AnimeSourceType { gogoanime, zoro, nineanime }

class AnimeProvider with ChangeNotifier {
  AnimeSource _currentSource = GogoAnimeService();
  
  void switchSource(AnimeSourceType type) {
    switch (type) {
      case AnimeSourceType.gogoanime:
        _currentSource = GogoAnimeService();
        break;
      case AnimeSourceType.zoro:
        _currentSource = ZoroSource();
        break;
      case AnimeSourceType.nineanime:
        _currentSource = NineAnimeSource();
        break;
    }
    notifyListeners();
  }
}
```

---

### 5. Add Push Notifications for New Episodes

**Step 1:** Add firebase_messaging dependency

```yaml
dependencies:
  firebase_messaging: ^14.7.9
  firebase_core: ^2.24.2
```

**Step 2:** Create notification service

```dart
// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  Future<void> initialize() async {
    await _messaging.requestPermission();
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Show local notification
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Navigate to anime details
    });
  }
  
  Future<void> subscribeToAnime(int animeId) async {
    await _messaging.subscribeToTopic('anime_$animeId');
  }
}
```

---

### 6. Add User Reviews/Ratings

**Step 1:** Create review model

```dart
// lib/models/review.dart
class Review {
  final String userId;
  final int animeId;
  final double rating;
  final String comment;
  final DateTime createdAt;
  
  Review({
    required this.userId,
    required this.animeId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
}
```

**Step 2:** Add review section in details screen

```dart
Widget _buildReviewSection() {
  return Column(
    children: [
      // Rating stars
      Row(
        children: List.generate(5, (index) {
          return IconButton(
            icon: Icon(
              index < userRating ? Icons.star : Icons.star_border,
              color: Colors.amber,
            ),
            onPressed: () => setState(() => userRating = index + 1),
          );
        }),
      ),
      
      // Comment input
      TextField(
        decoration: InputDecoration(
          hintText: 'Write your review...',
        ),
        maxLines: 3,
      ),
      
      // Submit button
      ElevatedButton(
        onPressed: _submitReview,
        child: Text('Submit Review'),
      ),
    ],
  );
}
```

---

### 7. Add Chromecast Support

**Step 1:** Add flutter_cast dependency

```yaml
dependencies:
  flutter_cast: ^1.0.0
```

**Step 2:** Implement cast button

```dart
import 'package:flutter_cast/flutter_cast.dart';

class VideoPlayerScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          CastButton(),
        ],
      ),
      body: // video player
    );
  }
}
```

---

### 8. Add Subtitle Support

**Step 1:** Install subtitle parser

```yaml
dependencies:
  subtitle_parser: ^1.0.0
```

**Step 2:** Add subtitle handling

```dart
Future<void> _loadSubtitles(String subtitleUrl) async {
  final response = await http.get(Uri.parse(subtitleUrl));
  final parser = SubtitleParser.fromString(response.body);
  
  // Add subtitles to video player
  _chewieController = ChewieController(
    videoPlayerController: _videoPlayerController!,
    subtitle: Subtitles(parser.subtitles),
    subtitleBuilder: (context, subtitle) => Container(
      padding: EdgeInsets.all(10),
      child: Text(
        subtitle,
        style: TextStyle(color: Colors.white, fontSize: 18),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
```

---

## 🔧 Performance Improvements

### Add Pagination

```dart
class AnimeProvider with ChangeNotifier {
  int _currentPage = 1;
  bool _hasMore = true;
  
  Future<void> loadMoreTrending() async {
    if (!_hasMore || _isLoadingTrending) return;
    
    _currentPage++;
    final newAnime = await _aniListService.getTrendingAnime(page: _currentPage);
    
    if (newAnime.isEmpty) {
      _hasMore = false;
    } else {
      _trendingAnime.addAll(newAnime);
    }
    
    notifyListeners();
  }
}
```

### Add Offline Mode

```dart
class CacheService {
  Future<void> cacheAnimeData(Anime anime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anime_${anime.id}', jsonEncode(anime.toJson()));
  }
  
  Future<Anime?> getCachedAnime(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('anime_$id');
    
    if (json != null) {
      return Anime.fromJson(jsonDecode(json));
    }
    return null;
  }
}
```

---

## 📦 Recommended Packages

```yaml
dependencies:
  # Already included
  http: ^1.2.0
  cached_network_image: ^3.3.1
  video_player: ^2.8.2
  chewie: ^1.8.1
  provider: ^6.1.1
  shimmer: ^3.0.0
  flutter_html: ^3.0.0-beta.2
  
  # For new features
  shared_preferences: ^2.2.2      # Local storage
  sqflite: ^2.3.0                 # SQLite database
  dio: ^5.4.0                     # Advanced HTTP client
  path_provider: ^2.1.1           # File paths
  firebase_messaging: ^14.7.9     # Push notifications
  flutter_local_notifications: ^16.3.0  # Local notifications
  flutter_cast: ^1.0.0            # Chromecast
  subtitle_parser: ^1.0.0         # Subtitles
  connectivity_plus: ^5.0.2       # Network status
  permission_handler: ^11.1.0     # Permissions
  share_plus: ^7.2.1              # Sharing
```

---

## 🎨 UI Enhancements

### Add Custom Theme

```dart
class AppTheme {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Color(0xFF2196F3),
    scaffoldBackgroundColor: Color(0xFF0D0D0D),
    cardColor: Color(0xFF1A1A1A),
    
    textTheme: TextTheme(
      headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(fontSize: 16),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF2196F3),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}
```

---

## 🧪 Testing

### Unit Tests

```dart
// test/services/anilist_service_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AniListService', () {
    test('getTrendingAnime returns list', () async {
      final service = AniListService();
      final result = await service.getTrendingAnime();
      
      expect(result, isA<List<Anime>>());
      expect(result.length, greaterThan(0));
    });
  });
}
```

### Widget Tests

```dart
// test/widgets/anime_card_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AnimeCard displays title', (WidgetTester tester) async {
    final anime = Anime(id: 1, title: 'Test Anime');
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimeCard(anime: anime),
        ),
      ),
    );
    
    expect(find.text('Test Anime'), findsOneWidget);
  });
}
```

---

Happy coding! 🚀
