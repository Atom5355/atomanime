# Quick Start Guide - ATOM ANIME

## 🚀 Running the App

### Step 1: Install Dependencies
```bash
flutter pub get
```

### Step 2: Run the App
Choose your platform:

**Android Emulator/Device:**
```bash
flutter run
```

**iOS Simulator/Device:**
```bash
flutter run -d ios
```

**Chrome (Web):**
```bash
flutter run -d chrome
```

**Windows:**
```bash
flutter run -d windows
```

## 📱 How to Use

### 1. Home Screen
- Browse **Trending Anime** in the top section
- Scroll down to see **Popular Anime**
- Tap on any anime card to view details

### 2. Search
- Tap the search icon (🔍) in the top right
- Type anime name to search in real-time
- Tap any result to view details

### 3. Anime Details
- View anime information, ratings, and synopsis
- Browse available episodes
- Tap "Play" on any episode to start streaming

### 4. Video Player
- Watch episodes with full video controls
- Use settings icon to change video quality
- Rotate device for fullscreen experience

## 🔧 Troubleshooting

### Videos Not Playing
- Check your internet connection
- Some anime may not have streaming links available
- Try a different episode or anime

### API Issues
- The app uses free APIs which may have rate limits
- If you see errors, wait a few minutes and try again

### Build Errors
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 🌐 APIs Used

1. **AniList API** - Anime metadata (free, no auth required)
2. **Consumet API** - Streaming links (free, community-maintained)

## 💡 Tips

- Use Wi-Fi for better streaming quality
- Some anime titles may differ between AniList and streaming sources
- Episodes load when you open anime details
- Search works best with English or Romaji titles

## ⚠️ Important Notes

- This is for educational purposes only
- Support official streaming platforms
- Respect copyright and licensing
- Internet connection required

## 🐛 Common Issues

**Q: Episode list is empty**
A: The anime might not be available on streaming sources, or the title doesn't match. Try popular anime like "Naruto" or "One Piece".

**Q: Video quality is low**
A: Use the settings icon in the video player to change quality if multiple options are available.

**Q: App is slow**
A: Clear app cache or check your internet connection.

## 📖 Project Structure

```
lib/
├── main.dart              # Entry point
├── models/                # Data models
├── providers/             # State management
├── screens/               # UI screens
├── services/              # API services
└── widgets/               # Reusable widgets
```

## 🎯 Next Steps

1. Run `flutter pub get` to install dependencies
2. Connect a device or start an emulator
3. Run `flutter run` to launch the app
4. Start exploring anime!

---

Enjoy watching anime with ATOM ANIME! 🎬✨
