import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../main.dart' show TvScale;

/// TV-optimized sidebar navigation for Android TV/Fire TV
/// Follows Android TV design guidelines with D-Pad navigation
class TvSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback? onSearchSelected;
  
  const TvSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.onSearchSelected,
  });
  
  @override
  State<TvSidebar> createState() => _TvSidebarState();
}

class _TvSidebarState extends State<TvSidebar> {
  int _focusedIndex = -1;
  bool _isExpanded = false;
  
  final List<TvSidebarItem> _items = [
    TvSidebarItem(icon: Icons.home, label: 'Home', index: 0),
    TvSidebarItem(icon: Icons.search, label: 'Search', index: 1),
    TvSidebarItem(icon: Icons.download_done, label: 'Downloads', index: 2),
    TvSidebarItem(icon: Icons.history, label: 'History', index: 3),
    TvSidebarItem(icon: Icons.settings, label: 'Settings', index: 4),
  ];
  
  @override
  Widget build(BuildContext context) {
    final tvScale = TvScale.factor(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isExpanded ? 200 * tvScale : 70 * tvScale,
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.95),
          border: Border(
            right: BorderSide(
              color: AppColors.glassBorder.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(5, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(height: 20 * tvScale),
            // Logo
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: _isExpanded ? 16 * tvScale : 12 * tvScale,
                vertical: 16 * tvScale,
              ),
              child: Row(
                mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(8 * tvScale),
                    decoration: BoxDecoration(
                      color: AppColors.neonYellowGlass,
                      borderRadius: BorderRadius.circular(10 * tvScale),
                      border: Border.all(color: AppColors.neonYellowGlassBorder),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: AppColors.neonYellow,
                      size: 24 * tvScale,
                    ),
                  ),
                  if (_isExpanded) ...[
                    SizedBox(width: 12 * tvScale),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ATOM',
                          style: TextStyle(
                            color: AppColors.neonYellow,
                            fontSize: 16 * tvScale,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'ANIME',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12 * tvScale,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 20 * tvScale),
            Divider(
              color: AppColors.glassBorder.withValues(alpha: 0.3),
              height: 1,
              indent: 16 * tvScale,
              endIndent: 16 * tvScale,
            ),
            SizedBox(height: 20 * tvScale),
            // Menu items
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 8 * tvScale),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildMenuItem(_items[index], index),
              ),
            ),
            // Profile at bottom
            _buildProfileItem(),
            SizedBox(height: 20 * tvScale),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMenuItem(TvSidebarItem item, int index) {
    final tvScale = TvScale.factor(context);
    final isSelected = widget.selectedIndex == item.index;
    
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _focusedIndex = hasFocus ? index : -1;
          if (hasFocus) _isExpanded = true;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            if (item.index == 1 && widget.onSearchSelected != null) {
              widget.onSearchSelected!();
            } else {
              widget.onItemSelected(item.index);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () {
              if (item.index == 1 && widget.onSearchSelected != null) {
                widget.onSearchSelected!();
              } else {
                widget.onItemSelected(item.index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.symmetric(vertical: 4 * tvScale),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * tvScale,
                vertical: 14 * tvScale,
              ),
              decoration: BoxDecoration(
                color: isFocused
                    ? AppColors.neonYellow
                    : isSelected
                        ? AppColors.neonYellow.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12 * tvScale),
                border: Border.all(
                  color: isFocused
                      ? AppColors.neonYellow
                      : isSelected
                          ? AppColors.neonYellow.withValues(alpha: 0.3)
                          : Colors.transparent,
                  width: isFocused ? 2 : 1,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.neonYellow.withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    color: isFocused
                        ? AppColors.background
                        : isSelected
                            ? AppColors.neonYellow
                            : AppColors.textSecondary,
                    size: 24 * tvScale,
                  ),
                  if (_isExpanded) ...[
                    SizedBox(width: 16 * tvScale),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isFocused
                            ? AppColors.background
                            : isSelected
                                ? AppColors.neonYellow
                                : AppColors.textPrimary,
                        fontSize: 14 * tvScale,
                        fontWeight: isSelected || isFocused ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildProfileItem() {
    final tvScale = TvScale.factor(context);
    
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) setState(() => _isExpanded = true);
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () => widget.onItemSelected(5), // Profile/logout
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.symmetric(horizontal: 8 * tvScale, vertical: 4 * tvScale),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * tvScale,
                vertical: 14 * tvScale,
              ),
              decoration: BoxDecoration(
                color: isFocused ? AppColors.neonYellow.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(12 * tvScale),
                border: Border.all(
                  color: isFocused ? AppColors.neonYellow : Colors.transparent,
                  width: isFocused ? 2 : 0,
                ),
              ),
              child: Row(
                mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 16 * tvScale,
                    backgroundColor: AppColors.neonYellow,
                    child: Icon(
                      Icons.person,
                      color: AppColors.background,
                      size: 18 * tvScale,
                    ),
                  ),
                  if (_isExpanded) ...[
                    SizedBox(width: 12 * tvScale),
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: isFocused ? AppColors.neonYellow : AppColors.textPrimary,
                        fontSize: 14 * tvScale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class TvSidebarItem {
  final IconData icon;
  final String label;
  final int index;
  
  TvSidebarItem({
    required this.icon,
    required this.label,
    required this.index,
  });
}
