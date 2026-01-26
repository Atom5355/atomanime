import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../main.dart' show TvInputDetector;

/// A cursor overlay for TV/D-Pad navigation
/// Shows a visible cursor that can be moved with D-Pad and clicks on Select
class TvCursorOverlay extends StatefulWidget {
  final Widget child;
  
  const TvCursorOverlay({super.key, required this.child});
  
  @override
  State<TvCursorOverlay> createState() => _TvCursorOverlayState();
}

class _TvCursorOverlayState extends State<TvCursorOverlay> with SingleTickerProviderStateMixin {
  // Cursor position
  Offset _cursorPosition = Offset.zero;
  bool _cursorVisible = false;
  bool _initialized = false;
  
  // Cursor movement speed (pixels per press)
  static const double _cursorSpeed = 25.0;
  static const double _cursorSpeedFast = 50.0; // When held
  
  // Cursor appearance
  static const double _cursorSize = 50.0;
  
  // Animation for cursor pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Track key hold for faster movement
  DateTime? _lastKeyTime;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Listen to hardware keyboard events globally
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }
  
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _pulseController.dispose();
    super.dispose();
  }
  
  void _initializeCursor(BuildContext context) {
    if (!_initialized) {
      // Start cursor in center of screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final size = MediaQuery.of(context).size;
          setState(() {
            _cursorPosition = Offset(size.width / 2, size.height / 2);
            _initialized = true;
          });
        }
      });
    }
  }
  
  void _moveCursor(Offset delta) {
    if (!mounted) return;
    
    final size = MediaQuery.of(context).size;
    
    // Calculate speed based on hold duration
    final now = DateTime.now();
    double speed = _cursorSpeed;
    if (_lastKeyTime != null && now.difference(_lastKeyTime!).inMilliseconds < 150) {
      speed = _cursorSpeedFast;
    }
    _lastKeyTime = now;
    
    setState(() {
      _cursorVisible = true;
      _cursorPosition = Offset(
        (_cursorPosition.dx + delta.dx * speed).clamp(20, size.width - 20),
        (_cursorPosition.dy + delta.dy * speed).clamp(20, size.height - 20),
      );
    });
    
    // Detect TV mode
    TvInputDetector.instance.onDpadInput();
  }
  
  void _simulateTap() {
    if (!_cursorVisible) return;
    
    // Dispatch pointer events to simulate a tap at cursor position
    final pointer = DateTime.now().millisecondsSinceEpoch % 1000000;
    
    final downEvent = PointerDownEvent(
      position: _cursorPosition,
      pointer: pointer,
      kind: PointerDeviceKind.touch,
    );
    
    final upEvent = PointerUpEvent(
      position: _cursorPosition,
      pointer: pointer,
      kind: PointerDeviceKind.touch,
    );
    
    // Dispatch events
    WidgetsBinding.instance.handlePointerEvent(downEvent);
    
    // Small delay before up to ensure gesture recognizers register
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        WidgetsBinding.instance.handlePointerEvent(upEvent);
      }
    });
  }
  
  bool _handleHardwareKey(KeyEvent event) {
    // Only handle key down and repeat events
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    
    final key = event.logicalKey;
    
    // D-Pad navigation
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(const Offset(0, -1));
      return true;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(const Offset(0, 1));
      return true;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCursor(const Offset(-1, 0));
      return true;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveCursor(const Offset(1, 0));
      return true;
    }
    
    // Select button (Enter, D-Pad center/select, gamepad A)
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _simulateTap();
      return true;
    }
    
    return false;
  }
  
  @override
  Widget build(BuildContext context) {
    _initializeCursor(context);
    
    return Stack(
      children: [
        // Main app content
        widget.child,
        
        // Cursor overlay (only visible when D-Pad used)
        if (_cursorVisible)
          Positioned(
            left: _cursorPosition.dx - _cursorSize / 2,
            top: _cursorPosition.dy - _cursorSize / 2,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _pulseAnimation.value,
                    child: Container(
                      width: _cursorSize,
                      height: _cursorSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.yellow,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.yellow.withOpacity(0.6),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.yellow,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.yellow.withOpacity(0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
