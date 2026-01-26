import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/anime_provider.dart';
import 'services/profile_service.dart';
import 'screens/home_screen.dart';
import 'screens/profile_selection_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/tv_cursor_overlay.dart';

// Global navigator key for mouse button navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Check if running on a desktop platform
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Check if this is likely a TV device (Android TV, Fire TV, etc.)
/// Detection is heuristic - checks for Android with no touch (leanback) features
bool get isTv {
  if (!Platform.isAndroid) return false;
  // On Android TV/Fire TV, we can detect via features
  // For now, assume Android TV if screen is large and no touch
  // A more robust solution would use platform channels to check android.software.leanback
  return false; // Will be set dynamically based on input type
}

/// Global flag to track if D-Pad input has been detected
/// (suggests TV or game controller usage)
class TvInputDetector extends ChangeNotifier {
  static final TvInputDetector instance = TvInputDetector._();
  TvInputDetector._();
  
  bool _hasDetectedDpadInput = false;
  bool get isLikelyTv => _hasDetectedDpadInput;
  
  void onDpadInput() {
    if (!_hasDetectedDpadInput) {
      _hasDetectedDpadInput = true;
      notifyListeners();
    }
  }
}

/// TV UI Scale factor - 1.5x for TV devices (50% bigger)
/// Use this to scale UI elements that need to be larger on TV
class TvScale {
  /// Get the scale factor based on whether this is a TV
  static double factor(BuildContext context) {
    // Check if D-Pad input detected (TV mode)
    if (TvInputDetector.instance.isLikelyTv) {
      return 1.5;
    }
    // Also check screen size - TVs are typically large displays viewed from distance
    final size = MediaQuery.of(context).size;
    final isLargeScreen = size.shortestSide > 600;
    // If Android with large screen, likely TV
    if (Platform.isAndroid && isLargeScreen) {
      return 1.5;
    }
    return 1.0;
  }
  
  /// Scale a value for TV
  static double scale(BuildContext context, double value) {
    return value * factor(context);
  }
  
  /// Check if we're in TV mode
  static bool isTvMode(BuildContext context) {
    return factor(context) > 1.0;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  // Initialize window_manager for fullscreen support (desktop only)
  if (isDesktop) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AnimeProvider()),
        ChangeNotifierProvider(create: (_) => ProfileService()),
        ChangeNotifierProvider.value(value: TvInputDetector.instance),
      ],
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          // Mouse back button (XButton1) = button index 3 (bitmask 8)
          // Mouse forward button (XButton2) = button index 4 (bitmask 16)
          if (event.buttons == kBackMouseButton) {
            // Back button pressed - go back in navigation
            if (navigatorKey.currentState?.canPop() ?? false) {
              navigatorKey.currentState?.pop();
            }
          } else if (event.buttons == kForwardMouseButton) {
            // Forward button - we can't go forward in Flutter's default navigator
            // But we could implement a history system if needed
            // For now, this is a placeholder
          }
        },
        child: Consumer<TvInputDetector>(
          builder: (context, tvDetector, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'ATOM ANIME',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              // Apply TV scaling via MediaQuery
              builder: (context, child) {
                // Check if TV mode based on D-Pad detection or screen size
                final isTvMode = tvDetector.isLikelyTv || 
                    (Platform.isAndroid && MediaQuery.of(context).size.shortestSide > 600);
                
                Widget result = child!;
                
                if (isTvMode) {
                  // Scale text by 1.5x for TV viewing distance
                  result = MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.5),
                    ),
                    child: result,
                  );
                }
                
                // Wrap with TV cursor overlay for D-Pad navigation on Android
                if (Platform.isAndroid) {
                  result = TvCursorOverlay(child: result);
                }
                
                return result;
              },
              // Start with profile selection, then navigate to home
              initialRoute: '/',
              routes: {
                '/': (context) => const ProfileSelectionScreen(),
                '/home': (context) => const HomeScreen(),
              },
            );
          },
        ),
      ),
    );
  }
}
