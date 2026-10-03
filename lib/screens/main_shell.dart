import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _i = 0;

  static const _pages = [
    FeedScreen(),
    SearchScreen(),
    MessagesScreen(),
    NotificationsScreen(),
  ];

  // Define nav items declaratively
  static const List<_NavItem> _navItems = [
    _NavItem(
      outline: 'assets/icons/nav_home_outline.svg',
      filled: 'assets/icons/nav_home_filled.svg',
    ),
    _NavItem(
      outline: 'assets/icons/nav_search.svg',
      filled: 'assets/icons/nav_search_filled.svg', // falls back to outline if missing
    ),
    _NavItem(
      outline: 'assets/icons/nav_chat_outline.svg',
      filled: 'assets/icons/nav_chat_filled.svg',
    ),
    _NavItem(
      outline: 'assets/icons/nav_heart_outline.svg',
      filled: 'assets/icons/nav_heart_filled.svg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _navItems.length,
                (idx) => _navButton(idx),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(int idx) {
    final active = _i == idx;
    final item = _navItems[idx];

    // Pick the SVG path — if you didn't export a filled search icon,
    // it falls back to the outline and only the color changes.
    final svgPath = active ? item.filled : item.outline;
    final color = active ? AppColors.red : Colors.grey.shade600;

    return GestureDetector(
      onTap: () => setState(() => _i = idx),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: SvgPicture.asset(
              svgPath,
              key: ValueKey('$svgPath-$active'),
              width: 26,
              height: 26,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String outline;
  final String filled;
  const _NavItem({required this.outline, required this.filled});
}
