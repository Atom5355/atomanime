import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../services/profile_service.dart';
import '../models/profile.dart';
import '../widgets/profile_dialogs.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;

/// Screen for selecting a profile on app startup
class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen>
    with SingleTickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  bool _isLoading = true;
  bool _isSelecting = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _initialize();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _profileService.initialize();

    // Check if already logged in (auto-login)
    if (_profileService.isLoggedIn) {
      if (mounted) {
        _navigateToHome();
      }
      return;
    }

    setState(() => _isLoading = false);
    _animationController.forward();
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  Future<void> _selectProfile(Profile profile) async {
    setState(() => _isSelecting = true);

    try {
      final requiresPin = await _profileService.requiresPin(profile.id);

      if (requiresPin) {
        if (!mounted) return;
        final success = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PinEntryDialog(profile: profile),
        );

        if (success == true && mounted) {
          _navigateToHome();
        }
      } else {
        final success =
            await _profileService.selectRememberedProfile(profile.id);
        if (success && mounted) {
          _navigateToHome();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSelecting = false);
      }
    }
  }

  Future<void> _showSignupDialog() async {
    final profile = await showDialog<Profile>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SignupDialog(),
    );

    if (profile != null && mounted) {
      _navigateToHome();
    }
  }

  Future<void> _showLoginDialog() async {
    final profile = await showDialog<Profile>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LoginDialog(),
    );

    if (profile != null && mounted) {
      _navigateToHome();
    }
  }

  Future<void> _removeProfile(Profile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        title: const Text('Remove Profile',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Remove "${profile.name}" from this device?\n\nYour profile data will be preserved and you can log back in.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _profileService.removeProfileFromDevice(profile.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: AppColors.neonYellow,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const NeonText(
                'Loading profiles...',
                fontSize: 16,
                glowIntensity: 0.3,
              ),
            ],
          ),
        ),
      );
    }

    final profiles = _profileService.deviceProfiles;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    children: [
                      const SizedBox(height: 48),

                      // App logo/title with neon glow
                      _buildLogo(),
                      const SizedBox(height: 16),
                      const NeonText(
                        'ATOM ANIME',
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        glowIntensity: 0.6,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Who\'s watching?',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Profile list
                      Expanded(
                        child: profiles.isEmpty
                            ? _buildEmptyState()
                            : _buildProfileGrid(profiles),
                      ),

                      // Bottom actions
                      _buildBottomActions(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final tvScale = TvScale.factor(context);
    
    return Container(
      width: 80 * tvScale,
      height: 80 * tvScale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonYellow,
            AppColors.neonYellowLight,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonGlowStrong,
            blurRadius: 30 * tvScale,
            spreadRadius: 5 * tvScale,
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: 48 * tvScale,
        color: AppColors.background,
      ),
    );
  }

  Widget _buildEmptyState() {
    final tvScale = TvScale.factor(context);
    
    return Center(
      child: GlassCard(
        padding: EdgeInsets.all(40 * tvScale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 80 * tvScale,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 20 * tvScale),
            const Text(
              'No profiles on this device',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8 * tvScale),
            const Text(
              'Create a new profile or login to get started',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileGrid(List<Profile> profiles) {
    final tvScale = TvScale.factor(context);
    
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24 * tvScale),
        child: Wrap(
          spacing: 24 * tvScale,
          runSpacing: 24 * tvScale,
          alignment: WrapAlignment.center,
          children: profiles.asMap().entries.map((entry) {
            return TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 400 + (entry.key * 100)),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: _buildProfileCard(entry.value),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProfileCard(Profile profile) {
    final profileColor = _parseColor(profile.avatarColor ?? '#FFD700');
    final tvScale = TvScale.factor(context);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            if (!_isSelecting) {
              _selectProfile(profile);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isSelecting ? null : () => _selectProfile(profile),
              onLongPress: _isSelecting ? null : () => _removeProfile(profile),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: isFocused ? (Matrix4.identity()..scale(1.08)) : Matrix4.identity(),
                transformAlignment: Alignment.center,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isSelecting ? 0.5 : 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20 * tvScale),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 160 * tvScale,
                        padding: EdgeInsets.all(20 * tvScale),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(20 * tvScale),
                          border: Border.all(
                            color: isFocused ? AppColors.neonYellow : profileColor.withValues(alpha: 0.3),
                            width: isFocused ? 3 * tvScale : 1.5 * tvScale,
                          ),
                          boxShadow: isFocused
                              ? [
                                  BoxShadow(
                                    color: AppColors.neonYellow.withValues(alpha: 0.5),
                                    blurRadius: 25 * tvScale,
                                    spreadRadius: 3 * tvScale,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: profileColor.withValues(alpha: 0.2),
                                    blurRadius: 20 * tvScale,
                                    spreadRadius: -5 * tvScale,
                                  ),
                                ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Avatar with glow
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: profileColor.withValues(alpha: 0.4),
                                    blurRadius: 15 * tvScale,
                                    spreadRadius: 2 * tvScale,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 42 * tvScale,
                                backgroundColor: profileColor,
                                child: Text(
                                  profile.name.isNotEmpty
                                      ? profile.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 32 * tvScale,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.background,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 16 * tvScale),

                            // Name
                            Text(
                              profile.name,
                              style: TextStyle(
                                fontSize: 16 * tvScale,
                                fontWeight: FontWeight.w600,
                                color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 8 * tvScale),

                            // Lock indicator
                            FutureBuilder<bool>(
                              future: _profileService.requiresPin(profile.id),
                              builder: (context, snapshot) {
                                final requiresPin = snapshot.data ?? true;
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10 * tvScale,
                                    vertical: 4 * tvScale,
                                  ),
                                  decoration: BoxDecoration(
                                    color: requiresPin
                                        ? AppColors.neonYellow.withValues(alpha: 0.1)
                                        : AppColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12 * tvScale),
                                    border: Border.all(
                                      color: requiresPin
                                          ? AppColors.neonYellow.withValues(alpha: 0.3)
                                          : AppColors.success.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        requiresPin ? Icons.lock : Icons.lock_open,
                                        size: 12 * tvScale,
                                        color: requiresPin
                                            ? AppColors.neonYellow
                                            : AppColors.success,
                                      ),
                                      SizedBox(width: 4 * tvScale),
                                      Text(
                                        requiresPin ? 'PIN' : 'Quick',
                                        style: TextStyle(
                                          fontSize: 11 * tvScale,
                                          color: requiresPin
                                              ? AppColors.neonYellow
                                              : AppColors.success,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomActions() {
    final tvScale = TvScale.factor(context);
    
    return Container(
      padding: EdgeInsets.all(24 * tvScale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Login button - outlined style with Focus for D-Pad
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  if (!_isSelecting) _showLoginDialog();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  child: OutlinedButton.icon(
                    onPressed: _isSelecting ? null : _showLoginDialog,
                    icon: Icon(Icons.login, size: 20 * tvScale),
                    label: Text('Login', style: TextStyle(fontSize: 14 * tvScale)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isFocused ? AppColors.background : AppColors.neonYellow,
                      backgroundColor: isFocused ? AppColors.neonYellow : Colors.transparent,
                      side: BorderSide(
                        color: isFocused ? AppColors.neonYellow : AppColors.neonYellow.withValues(alpha: 0.5),
                        width: isFocused ? 2 : 1,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 28 * tvScale, vertical: 14 * tvScale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14 * tvScale),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: 16 * tvScale),

          // Create profile button - neon style with Focus for D-Pad
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  if (!_isSelecting) _showSignupDialog();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: isFocused ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14 * tvScale),
                    boxShadow: [
                      BoxShadow(
                        color: isFocused ? AppColors.neonYellow.withValues(alpha: 0.6) : AppColors.neonGlow,
                        blurRadius: isFocused ? 25 : 15,
                        spreadRadius: isFocused ? 2 : -2,
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isSelecting ? null : _showSignupDialog,
                    icon: Icon(Icons.person_add, size: 20 * tvScale),
                    label: Text('Create Profile', style: TextStyle(fontSize: 14 * tvScale)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonYellow,
                      foregroundColor: AppColors.background,
                      padding: EdgeInsets.symmetric(horizontal: 28 * tvScale, vertical: 14 * tvScale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14 * tvScale),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
