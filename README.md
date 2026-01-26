# ATOM ANIME - Anime Streaming App

A beautiful, feature-rich anime streaming application built with Flutter. Stream your favorite anime using AniList API for anime data and Consumet API (GogoAnime) for streaming.

## ⚠️ Disclaimer

This is a **non-commercial, educational project** for learning purposes only. Please support official anime streaming platforms.

## ✨ Features

- **Browse Trending & Popular Anime**: Discover the latest and most popular anime series
- **Advanced Search**: Find any anime with real-time search functionality
- **Detailed Anime Information**: View synopsis, ratings, genres, episode count, and more
- **Episode Streaming**: Watch episodes with an integrated video player
- **Multiple Quality Options**: Choose from different video quality settings
- **Beautiful UI**: Dark-themed, modern interface with smooth animations
- **Cached Images**: Fast image loading with caching support

## 🛠️ Technologies Used

- **Flutter**: Cross-platform mobile framework
- **Provider**: State management
- **AniList GraphQL API**: Anime metadata and information
- **Consumet API**: Anime streaming links (GogoAnime)
- **Chewie**: Video player with controls
- **Cached Network Image**: Image caching and loading
- **Shimmer**: Loading placeholders

## 📦 Dependencies

```yaml
dependencies:
  http: ^1.2.0
  cached_network_image: ^3.3.1
  video_player: ^2.8.2
  chewie: ^1.8.1
  provider: ^6.1.1
  shimmer: ^3.0.0
  flutter_html: ^3.0.0-beta.2
  url_launcher: ^6.2.4
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (>=3.10.4)
- Dart SDK
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio (recommended IDEs)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd atomanime
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
# For Android
flutter run

# For iOS
flutter run -d ios

# For Web
flutter run -d chrome
```

## 📱 Supported Platforms

- ✅ Android
- ✅ iOS
- ✅ Web
- ✅ Windows
- ✅ macOS
- ✅ Linux

## 🏗️ Project Structure

```
lib/
├── main.dart                          # App entry point
├── models/
│   ├── anime.dart                     # Anime data model
│   └── episode.dart                   # Episode & streaming link models
├── providers/
│   └── anime_provider.dart            # State management
├── screens/
│   ├── home_screen.dart               # Home page with trending/popular
│   ├── search_screen.dart             # Search functionality
│   ├── anime_details_screen.dart      # Anime details & episodes
│   └── video_player_screen.dart       # Video player
└── services/
    ├── anilist_service.dart           # AniList API integration
    └── gogoanime_service.dart         # GogoAnime/Consumet API
```

## 🔑 API Information

### AniList API
- **URL**: https://graphql.anilist.co
- **Type**: GraphQL
- **Auth**: No authentication required for basic queries
- **Rate Limit**: 90 requests per minute

### Consumet API (GogoAnime)
- **URL**: https://api.consumet.org/anime/gogoanime
- **Type**: REST
- **Note**: Free and open-source API for anime streaming

## 🎨 Features Breakdown

### Home Screen
- Displays trending anime in a horizontal scrollable list
- Shows popular anime below trending section
- Beautiful card-based UI with cover images
- Skeleton loading with shimmer effect

### Search Screen
- Real-time search as you type
- Grid layout for search results
- Displays anime ratings and cover images

### Anime Details Screen
- Large banner/cover image
- Comprehensive anime information
- Expandable synopsis
- Genre tags
- Episode list with play buttons

### Video Player Screen
- Full-featured video player with Chewie
- Multiple quality options
- Play/pause, seek, volume controls
- Fullscreen support
- Landscape/portrait orientation support

## 🔧 Configuration

### Internet Permissions

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## 🐛 Known Issues & Limitations

- Some anime might not have streaming links available
- Video playback depends on external API availability
- Network connection required for all features
- Some videos might not play due to regional restrictions

## 🚧 Future Enhancements

- [ ] Favorites/Watchlist functionality
- [ ] Download episodes for offline viewing
- [ ] Continue watching feature
- [ ] User authentication
- [ ] Comments and ratings
- [ ] Notification for new episodes
- [ ] Multi-language support
- [ ] Cast to TV support

## 📄 License

This project is for educational purposes only. All anime content belongs to their respective owners.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

## 👏 Acknowledgments

- [AniList](https://anilist.co/) for providing the anime database API
- [Consumet](https://github.com/consumet/api.consumet.org) for the streaming API
- [GogoAnime](https://gogoanime.com/) for anime streaming content
- Flutter community for amazing packages

## 📞 Support

For support, please open an issue in the repository.

---

**Note**: This is a non-commercial project created for educational purposes. Please support official anime streaming platforms and creators.
