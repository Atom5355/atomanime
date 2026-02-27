import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Universal focusable widget that works on PC (mouse/keyboard), Android (touch), and TV (D-Pad).
/// Wraps any interactive element with proper focus handling, visual indicators, and input support.
class FocusableWidget extends StatefulWidget {
  final Widget Function(BuildContext context, bool isFocused, bool isHovered) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool showFocusBorder;
  final double focusBorderRadius;
  final double focusScale;
  final EdgeInsetsGeometry? focusPadding;
  final Color? focusColor;

  const FocusableWidget({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.showFocusBorder = false,
    this.focusBorderRadius = 12,
    this.focusScale = 1.0,
    this.focusPadding,
    this.focusColor,
  });

  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  bool _isFocused = false;
  bool _isHovered = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || widget.onSelect == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onSelect?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (mounted) setState(() => _isFocused = focused);
      },
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (mounted) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onSelect : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: (_isFocused && widget.focusScale != 1.0)
                ? Matrix4.diagonal3Values(widget.focusScale, widget.focusScale, 1.0)
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            padding: widget.focusPadding,
            decoration: (widget.showFocusBorder && _isFocused)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.focusBorderRadius),
                    border: Border.all(
                      color: widget.focusColor ?? AppColors.neonYellow,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.focusColor ?? AppColors.neonYellow).withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: widget.builder(context, _isFocused, _isHovered),
          ),
        ),
      ),
    );

    return child;
  }
}

/// A horizontally scrollable list that supports:
/// - Mouse wheel scrolling (PC)
/// - Arrow key / D-Pad navigation between items
/// - Touch scrolling (Android)
/// - Auto-scrolls to keep focused item visible
/// - Optional scroll arrow buttons on hover
class FocusableHorizontalList extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index, bool isFocused) itemBuilder;
  final double itemWidth;
  final double itemSpacing;
  final double height;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final String? sectionLabel; // For accessibility

  const FocusableHorizontalList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.itemWidth = 165,
    this.itemSpacing = 12,
    this.height = 260,
    this.padding,
    this.scrollController,
    this.sectionLabel,
  });

  @override
  State<FocusableHorizontalList> createState() => _FocusableHorizontalListState();
}

class _FocusableHorizontalListState extends State<FocusableHorizontalList> {
  late ScrollController _scrollController;
  int _focusedIndex = -1;
  bool _isHovered = false;
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    _focusNodes.clear();
    for (int i = 0; i < widget.itemCount; i++) {
      _focusNodes.add(FocusNode(debugLabel: '${widget.sectionLabel ?? 'list'}_item_$i'));
    }
  }

  @override
  void didUpdateWidget(FocusableHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      // Dispose old focus nodes and create new ones
      for (final node in _focusNodes) {
        node.dispose();
      }
      _initFocusNodes();
    }
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final targetOffset = index * (widget.itemWidth + widget.itemSpacing);
    final viewportWidth = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Center the focused item in view
    double scrollTo = targetOffset - (viewportWidth / 2) + (widget.itemWidth / 2);
    scrollTo = scrollTo.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      scrollTo,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final newOffset = (currentOffset + delta).clamp(0.0, maxScroll);
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _handleItemFocus(int index) {
    setState(() => _focusedIndex = index);
    _scrollToIndex(index);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_focusedIndex > 0) {
        _focusNodes[_focusedIndex - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_focusedIndex < widget.itemCount - 1) {
        _focusNodes[_focusedIndex + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // The scrollable list with mouse wheel support
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  // Convert vertical scroll to horizontal on PC
                  _scrollBy(event.scrollDelta.dy);
                }
              },
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.itemCount,
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: widget.itemWidth + widget.itemSpacing,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: widget.itemSpacing / 2),
                      child: Focus(
                        focusNode: (index < _focusNodes.length) ? _focusNodes[index] : null,
                        onFocusChange: (focused) {
                          if (focused) {
                            _handleItemFocus(index);
                          } else {
                            // When an item loses focus, check if any item in this list still has focus
                            // If not, reset the highlight to prevent stale highlights across sections
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              final anyFocused = _focusNodes.any((node) => node.hasFocus);
                              if (!anyFocused && _focusedIndex != -1) {
                                setState(() => _focusedIndex = -1);
                              }
                            });
                          }
                        },
                        onKeyEvent: _handleKeyEvent,
                        child: widget.itemBuilder(
                          context,
                          index,
                          _focusedIndex == index,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Left scroll arrow (PC hover)
            if (_isHovered && !Platform.isAndroid && !Platform.isIOS)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _buildScrollArrow(
                  icon: Icons.chevron_left,
                  onTap: () => _scrollBy(-300),
                ),
              ),
            // Right scroll arrow (PC hover)
            if (_isHovered && !Platform.isAndroid && !Platform.isIOS)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildScrollArrow(
                  icon: Icons.chevron_right,
                  onTap: () => _scrollBy(300),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollArrow({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.background.withValues(alpha: 0.95),
              AppColors.background.withValues(alpha: 0.0),
            ],
            begin: icon == Icons.chevron_left ? Alignment.centerLeft : Alignment.centerRight,
            end: icon == Icons.chevron_left ? Alignment.centerRight : Alignment.centerLeft,
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.glass,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 24),
          ),
        ),
      ),
    );
  }
}

/// A focusable grid that supports 2D D-Pad navigation (up/down/left/right).
/// Used for episode grids, search results, etc.
class FocusableGrid extends StatefulWidget {
  final int itemCount;
  final int crossAxisCount;
  final Widget Function(BuildContext context, int index, bool isFocused) itemBuilder;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;

  const FocusableGrid({
    super.key,
    required this.itemCount,
    required this.crossAxisCount,
    required this.itemBuilder,
    this.childAspectRatio = 1.3,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 12,
    this.padding,
    this.scrollController,
  });

  @override
  State<FocusableGrid> createState() => _FocusableGridState();
}

class _FocusableGridState extends State<FocusableGrid> {
  int _focusedIndex = -1;
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
  }

  void _initFocusNodes() {
    _focusNodes.clear();
    for (int i = 0; i < widget.itemCount; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'grid_item_$i'));
    }
  }

  @override
  void didUpdateWidget(FocusableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _initFocusNodes();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final cols = widget.crossAxisCount;
    int newIndex = index;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      newIndex = index - 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      newIndex = index + 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      newIndex = index - cols;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      newIndex = index + cols;
    } else {
      return KeyEventResult.ignored;
    }

    if (newIndex >= 0 && newIndex < widget.itemCount && newIndex < _focusNodes.length) {
      _focusNodes[newIndex].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.scrollController,
      padding: widget.padding ?? const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
      ),
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        return Focus(
          focusNode: (index < _focusNodes.length) ? _focusNodes[index] : null,
          onFocusChange: (focused) {
            if (focused) {
              setState(() => _focusedIndex = index);
            } else {
              // Reset highlight when focus leaves this grid entirely
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final anyFocused = _focusNodes.any((node) => node.hasFocus);
                if (!anyFocused && _focusedIndex != -1) {
                  setState(() => _focusedIndex = -1);
                }
              });
            }
          },
          onKeyEvent: (node, event) => _handleKeyEvent(node, event, index),
          child: widget.itemBuilder(context, index, _focusedIndex == index),
        );
      },
    );
  }
}

/// A text form field wrapper that works well with D-Pad navigation.
/// Shows visual focus indicator and handles D-Pad select to activate keyboard.
class DpadFormField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;

  const DpadFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  State<DpadFormField> createState() => _DpadFormFieldState();
}

class _DpadFormFieldState extends State<DpadFormField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: AppColors.neonYellow.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        validator: widget.validator,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        textInputAction: widget.textInputAction,
        textAlign: widget.textAlign,
        style: widget.style ?? const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          labelStyle: TextStyle(
            color: _isFocused ? AppColors.neonYellow : AppColors.textMuted,
          ),
          hintStyle: TextStyle(color: AppColors.textMuted),
          prefixIcon: widget.prefixIcon != null
              ? Icon(
                  widget.prefixIcon,
                  color: _isFocused ? AppColors.neonYellow : AppColors.textMuted,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.neonYellow, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error, width: 2),
          ),
          counterStyle: TextStyle(color: AppColors.textMuted),
          filled: true,
          fillColor: _isFocused
              ? AppColors.neonYellow.withValues(alpha: 0.05)
              : AppColors.glass,
        ),
      ),
    );
  }
}

/// A button designed for all platforms - touch, mouse, and D-Pad.
/// Provides consistent focus visuals across all input methods.
class UniversalButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool autofocus;
  final FocusNode? focusNode;
  final Color? color;
  final Color? textColor;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  const UniversalButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isPrimary = true,
    this.autofocus = false,
    this.focusNode,
    this.color,
    this.textColor,
    this.fontSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onPressed,
      focusScale: 1.05,
      builder: (context, isFocused, isHovered) {
        final bgColor = isPrimary
            ? (color ?? AppColors.neonYellow)
            : Colors.transparent;
        final fgColor = isPrimary
            ? (textColor ?? AppColors.background)
            : (color ?? AppColors.neonYellow);
        final borderColor = isPrimary
            ? (isFocused ? AppColors.textPrimary : Colors.transparent)
            : (isFocused
                ? (color ?? AppColors.neonYellow)
                : (color ?? AppColors.neonYellow).withValues(alpha: 0.5));

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: isFocused && !isPrimary ? (color ?? AppColors.neonYellow) : bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: isFocused ? 2.5 : 1.5,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: (color ?? AppColors.neonYellow).withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ]
                : (isPrimary
                    ? [
                        BoxShadow(
                          color: (color ?? AppColors.neonYellow).withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ]
                    : null),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: isFocused && !isPrimary ? AppColors.background : fgColor,
                  size: (fontSize ?? 14) + 4,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isFocused && !isPrimary ? AppColors.background : fgColor,
                  fontSize: fontSize ?? 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A focusable menu item for custom dropdown/menu replacements.
/// Replaces PopupMenuButton items for D-Pad compatibility.
class FocusableMenuItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onSelect;
  final Color? iconColor;
  final Color? textColor;
  final bool autofocus;

  const FocusableMenuItem({
    super.key,
    required this.label,
    this.icon,
    required this.onSelect,
    this.iconColor,
    this.textColor,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, isFocused, isHovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isFocused
                ? AppColors.neonYellow.withValues(alpha: 0.15)
                : (isHovered ? AppColors.glass : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: isFocused
                ? Border.all(color: AppColors.neonYellow.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: isFocused
                      ? AppColors.neonYellow
                      : (iconColor ?? AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isFocused
                        ? AppColors.neonYellow
                        : (textColor ?? AppColors.textPrimary),
                    fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isFocused)
                Icon(
                  Icons.chevron_right,
                  color: AppColors.neonYellow.withValues(alpha: 0.7),
                  size: 18,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A custom focusable menu that replaces PopupMenuButton for D-Pad compatibility.
/// Shows a modal overlay with focusable menu items.
class FocusableMenu {
  static Future<T?> show<T>({
    required BuildContext context,
    required List<FocusableMenuEntry<T>> items,
    Offset? offset,
    Widget? header,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return _FocusableMenuDialog<T>(
          items: items,
          header: header,
        );
      },
    );
  }
}

class FocusableMenuEntry<T> {
  final String label;
  final IconData? icon;
  final T? value;
  final Color? iconColor;
  final Color? textColor;
  final bool isDivider;

  const FocusableMenuEntry({
    required this.label,
    this.icon,
    required this.value,
    this.iconColor,
    this.textColor,
    this.isDivider = false,
  });

  FocusableMenuEntry.divider()
      : label = '',
        icon = null,
        value = null,
        iconColor = null,
        textColor = null,
        isDivider = true;
}

class _FocusableMenuDialog<T> extends StatelessWidget {
  final List<FocusableMenuEntry<T>> items;
  final Widget? header;

  const _FocusableMenuDialog({
    required this.items,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: header!,
                ),
                Divider(color: AppColors.glassBorder, height: 1),
              ],
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: items.asMap().entries.map((entry) {
                      final item = entry.value;
                      if (item.isDivider) {
                        return Divider(
                          color: AppColors.glassBorder,
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        );
                      }
                      return FocusableMenuItem(
                        autofocus: entry.key == 0,
                        label: item.label,
                        icon: item.icon,
                        iconColor: item.iconColor,
                        textColor: item.textColor,
                        onSelect: () => Navigator.of(context).pop(item.value),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Close hint
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Press Back to close',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A focusable checkbox with proper D-Pad support
class FocusableCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? subtitle;

  const FocusableCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWidget(
      onSelect: () => onChanged(!value),
      builder: (context, isFocused, isHovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isFocused
                ? AppColors.neonYellow.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isFocused
                ? Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? AppColors.neonYellow : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: value
                        ? AppColors.neonYellow
                        : (isFocused ? AppColors.neonYellow : AppColors.glassBorder),
                    width: isFocused ? 2 : 1.5,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check, size: 16, color: AppColors.background)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                        fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
