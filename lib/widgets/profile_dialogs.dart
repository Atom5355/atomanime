import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/profile_service.dart';
import '../models/profile.dart';
import '../theme/app_theme.dart';
import 'focusable_widget.dart';

/// Dialog for creating a new profile - fully accessible on PC, Android, and TV
class SignupDialog extends StatefulWidget {
  const SignupDialog({super.key});

  @override
  State<SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends State<SignupDialog> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  // Focus nodes for explicit traversal order
  final _nameFocus = FocusNode(debugLabel: 'signup_name');
  final _pinFocus = FocusNode(debugLabel: 'signup_pin');
  final _confirmPinFocus = FocusNode(debugLabel: 'signup_confirm_pin');
  
  bool _rememberPin = true;
  bool _isLoading = false;
  String? _error;
  int _selectedColorIndex = 0;

  final _avatarColors = [
    '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3',
    '#03A9F4', '#00BCD4', '#009688', '#4CAF50', '#8BC34A',
    '#FFC107', '#FF9800', '#FF5722',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _nameFocus.dispose();
    _pinFocus.dispose();
    _confirmPinFocus.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await ProfileService().createProfile(
        name: _nameController.text.trim(),
        pin: _pinController.text,
        avatarColor: _avatarColors[_selectedColorIndex],
      );

      if (profile != null) {
        await ProfileService().login(
          name: profile.name,
          pin: _pinController.text,
          rememberPin: _rememberPin,
        );
        
        if (mounted) {
          Navigator.of(context).pop(profile);
        }
      } else {
        setState(() {
          _error = 'Failed to create profile. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 440,
            constraints: const BoxConstraints(maxHeight: 620),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NeonText(
                      'Create Profile',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    
                    // Avatar color selection - focusable
                    const Text(
                      'Choose Avatar Color',
                      style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    _buildColorPicker(),
                    const SizedBox(height: 22),

                    // Profile name - DpadFormField
                    DpadFormField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      autofocus: true,
                      labelText: 'Profile Name',
                      prefixIcon: Icons.person,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _pinFocus.requestFocus(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a profile name';
                        }
                        if (value.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // PIN
                    DpadFormField(
                      controller: _pinController,
                      focusNode: _pinFocus,
                      labelText: '5-Digit PIN',
                      prefixIcon: Icons.lock,
                      obscureText: true,
                      maxLength: 5,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _confirmPinFocus.requestFocus(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a PIN';
                        }
                        if (value.length != 5) {
                          return 'PIN must be exactly 5 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),

                    // Confirm PIN
                    DpadFormField(
                      controller: _confirmPinController,
                      focusNode: _confirmPinFocus,
                      labelText: 'Confirm PIN',
                      prefixIcon: Icons.lock_outline,
                      obscureText: true,
                      maxLength: 5,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signup(),
                      validator: (value) {
                        if (value != _pinController.text) {
                          return 'PINs do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // Remember PIN - focusable checkbox
                    FocusableCheckbox(
                      value: _rememberPin,
                      onChanged: (value) => setState(() => _rememberPin = value),
                      label: 'Remember PIN on this device',
                      subtitle: 'Skip PIN entry next time',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Buttons - focusable
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        UniversalButton(
                          label: 'Cancel',
                          isPrimary: false,
                          onPressed: _isLoading ? null : () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        UniversalButton(
                          label: _isLoading ? 'Creating...' : 'Create Profile',
                          icon: Icons.person_add,
                          onPressed: _isLoading ? null : _signup,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(_avatarColors.length, (index) {
        final isSelected = _selectedColorIndex == index;
        return FocusableWidget(
          onSelect: () => setState(() => _selectedColorIndex = index),
          builder: (context, isFocused, isHovered) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _parseColor(_avatarColors[index]),
                shape: BoxShape.circle,
                border: (isSelected || isFocused)
                    ? Border.all(
                        color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                        width: 3,
                      )
                    : null,
                boxShadow: (isSelected || isFocused)
                    ? [
                        BoxShadow(
                          color: isFocused
                              ? AppColors.neonYellow.withValues(alpha: 0.6)
                              : _parseColor(_avatarColors[index]).withValues(alpha: 0.6),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            );
          },
        );
      }),
    );
  }
}

/// Dialog for logging into an existing profile - fully accessible on PC, Android, and TV
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  // Focus nodes for explicit traversal order
  final _nameFocus = FocusNode(debugLabel: 'login_name');
  final _pinFocus = FocusNode(debugLabel: 'login_pin');
  
  bool _rememberPin = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _nameFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await ProfileService().login(
        name: _nameController.text.trim(),
        pin: _pinController.text,
        rememberPin: _rememberPin,
      );

      if (profile != null && mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NeonText(
                      'Login to Profile',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your profile name and PIN',
                      style: TextStyle(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Profile name - DpadFormField with auto-focus
                    DpadFormField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      autofocus: true,
                      labelText: 'Profile Name',
                      prefixIcon: Icons.person,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _pinFocus.requestFocus(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your profile name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // PIN - DpadFormField
                    DpadFormField(
                      controller: _pinController,
                      focusNode: _pinFocus,
                      labelText: '5-Digit PIN',
                      prefixIcon: Icons.lock,
                      obscureText: true,
                      maxLength: 5,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your PIN';
                        }
                        if (value.length != 5) {
                          return 'PIN must be 5 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // Remember PIN - focusable checkbox
                    FocusableCheckbox(
                      value: _rememberPin,
                      onChanged: (value) => setState(() => _rememberPin = value),
                      label: 'Remember PIN on this device',
                      subtitle: 'Skip PIN entry next time',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Buttons - focusable
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        UniversalButton(
                          label: 'Cancel',
                          isPrimary: false,
                          onPressed: _isLoading ? null : () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        UniversalButton(
                          label: _isLoading ? 'Logging in...' : 'Login',
                          icon: Icons.login,
                          onPressed: _isLoading ? null : _login,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for entering PIN to access a profile - fully accessible on PC, Android, and TV
class PinEntryDialog extends StatefulWidget {
  final Profile profile;
  
  const PinEntryDialog({super.key, required this.profile});

  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog> {
  final _pinController = TextEditingController();
  final _pinFocus = FocusNode(debugLabel: 'pin_entry');
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  Future<void> _submit() async {
    if (_pinController.text.length != 5) {
      setState(() => _error = 'PIN must be 5 digits');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await ProfileService().loginWithId(
        profileId: widget.profile.id,
        pin: _pinController.text,
      );

      if (profile != null && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 370,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar with glow
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _parseColor(widget.profile.avatarColor ?? '#673AB7').withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: _parseColor(widget.profile.avatarColor ?? '#673AB7'),
                      child: Text(
                        widget.profile.name.isNotEmpty 
                            ? widget.profile.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  NeonText(
                    widget.profile.name,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your PIN to continue',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 26),

                  // PIN input - DpadFormField with auto-focus
                  DpadFormField(
                    controller: _pinController,
                    focusNode: _pinFocus,
                    autofocus: true,
                    labelText: 'PIN',
                    prefixIcon: Icons.lock,
                    obscureText: true,
                    maxLength: 5,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 10,
                      color: AppColors.textPrimary,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Buttons - focusable
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      UniversalButton(
                        label: 'Cancel',
                        isPrimary: false,
                        onPressed: _isLoading ? null : () => Navigator.pop(context, false),
                      ),
                      const SizedBox(width: 12),
                      UniversalButton(
                        label: _isLoading ? 'Unlocking...' : 'Unlock',
                        icon: Icons.lock_open,
                        onPressed: _isLoading ? null : _submit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
