import 'package:flutter/material.dart';
import 'dart:ui';

/// ATOM ANIME Theme System
/// Gloss black background with neon yellow accents and glassmorphism effects

class AppColors {
  // Backgrounds - Gloss black
  static const Color background = Color(0xFF0A0A0A);
  static const Color backgroundSecondary = Color(0xFF101010);
  static const Color surface = Color(0xFF141414);
  
  // Glass effects
  static Color glass = Colors.white.withValues(alpha: 0.03);
  static Color glassLight = Colors.white.withValues(alpha: 0.06);
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
  static Color glassBorderLight = Colors.white.withValues(alpha: 0.12);
  
  // Card border - Neon light gray
  static Color cardBorder = Colors.white.withValues(alpha: 0.15);
  static Color cardBorderHover = Colors.white.withValues(alpha: 0.25);
  
  // Neon Yellow (Primary accent) - Semi-transparent for glassmorphism
  static const Color neonYellow = Color(0xFFFFD700);
  static const Color neonYellowLight = Color(0xFFFFC107);
  static const Color neonYellowBright = Color(0xFFFFEB3B);
  static Color neonYellowGlass = const Color(0xFFFFD700).withValues(alpha: 0.15);
  static Color neonYellowGlassBorder = const Color(0xFFFFD700).withValues(alpha: 0.3);
  
  // Neon glow colors
  static Color neonGlow = const Color(0xFFFFD700).withValues(alpha: 0.25);
  static Color neonGlowStrong = const Color(0xFFFFD700).withValues(alpha: 0.4);
  
  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF666666);
  
  // Status colors
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);
  static const Color info = Color(0xFF60A5FA);
  
  // Category colors
  static const Color sub = Color(0xFF4ADE80);
  static const Color dub = Color(0xFFFB923C);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.neonYellow,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Inter',
      
      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonYellow,
        secondary: AppColors.neonYellowLight,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      
      cardTheme: CardThemeData(
        color: AppColors.glass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonYellow,
          foregroundColor: AppColors.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.neonYellow,
          side: const BorderSide(color: AppColors.neonYellow),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.neonYellow,
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glass,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neonYellow, width: 2),
        ),
      ),
      
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.neonYellow,
      ),
      
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.neonYellow,
        inactiveTrackColor: AppColors.glass,
        thumbColor: AppColors.neonYellow,
        overlayColor: AppColors.neonGlow,
      ),
      
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.neonYellow;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.background),
        side: BorderSide(color: AppColors.glassBorder, width: 2),
      ),
      
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Glassmorphism card with blur effect and subtle border
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool hasGlow;
  final Color? glowColor;
  final double blur;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.hasGlow = false,
    this.glowColor,
    this.blur = 10,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: glowColor ?? AppColors.neonGlow,
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: hasGlow
                    ? (glowColor ?? AppColors.neonYellow).withValues(alpha: 0.3)
                    : AppColors.glassBorder,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null || onLongPress != null) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      );
    }
    return card;
  }
}

/// Neon text with glow effect
class NeonText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final double glowIntensity;
  final TextAlign? textAlign;

  const NeonText(
    this.text, {
    super.key,
    this.fontSize = 16,
    this.fontWeight = FontWeight.normal,
    this.color,
    this.glowIntensity = 0.5,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppColors.neonYellow;
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: [
          Shadow(
            color: textColor.withValues(alpha: glowIntensity),
            blurRadius: 10,
          ),
          Shadow(
            color: textColor.withValues(alpha: glowIntensity * 0.5),
            blurRadius: 20,
          ),
        ],
      ),
    );
  }
}

/// Animated gradient background - Now solid gloss black
class AnimatedGradientBackground extends StatelessWidget {
  final Widget? child;
  final List<Color>? colors;

  const AnimatedGradientBackground({
    super.key,
    this.child,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Solid gloss black background
    return Container(
      color: AppColors.background,
      child: child,
    );
  }
}

/// Neon icon button with glow
class NeonIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final bool isActive;

  const NeonIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 24,
    this.color,
    this.isActive = false,
  });

  @override
  State<NeonIconButton> createState() => _NeonIconButtonState();
}

class _NeonIconButtonState extends State<NeonIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ?? 
        (widget.isActive || _isHovered ? AppColors.neonYellow : AppColors.textSecondary);
    
    final button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered || widget.isActive 
                ? AppColors.neonYellow.withValues(alpha: 0.1) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: iconColor,
            shadows: _isHovered || widget.isActive
                ? [
                    Shadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Category chip (SUB/DUB badges)
class CategoryChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSub;
  final bool isSelected;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.label,
    this.count,
    this.isSub = true,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSub ? AppColors.sub : AppColors.dub;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading shimmer with neon effect
class NeonShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const NeonShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.surface.withValues(alpha: 0.5),
            AppColors.surface,
          ],
        ),
      ),
    );
  }
}

/// Gradient border container
class GradientBorderContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;

  const GradientBorderContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.borderWidth = 1.5,
    this.padding,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient ??
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.neonYellow.withValues(alpha: 0.5),
                AppColors.neonYellow.withValues(alpha: 0.1),
              ],
            ),
      ),
      child: Container(
        margin: EdgeInsets.all(borderWidth),
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(borderRadius - borderWidth),
        ),
        child: child,
      ),
    );
  }
}
