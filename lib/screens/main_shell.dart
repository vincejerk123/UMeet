import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late PageController _pageController;

  static const _pages = [
    FeedScreen(),
    SearchScreen(),
    MessagesScreen(),
    NotificationsScreen(),
  ];

  static const _navItems = [
    _NavItem(
      outline: 'assets/icons/nav_home_outline.svg',
      filled: 'assets/icons/nav_home_filled.svg',
    ),
    _NavItem(
      outline: 'assets/icons/nav_search.svg',
      filled: 'assets/icons/nav_search_filled.svg',
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
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _i);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTap(int idx) {
    if (idx == _i) return;
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    setState(() => _i = idx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // swipe disabled
        itemCount: _pages.length,
        onPageChanged: (i) {
          if (i != _i) setState(() => _i = i);
        },
        itemBuilder: (context, i) {
          return _ParallaxPage(
            controller: _pageController,
            index: i,
            child: _KeepAlive(child: _pages[i]),
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFEEEEEE))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(
                _navItems.length,
                (idx) => Expanded(
                  child: _NavButton(
                    item: _navItems[idx],
                    active: _i == idx,
                    onTap: () => _onTap(idx),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════
//  Parallax: outgoing page shrinks + dims slightly while
//  the incoming page slides in. Gives a premium iOS feel.
// ════════════════════════════════════════════════════
class _ParallaxPage extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;

  const _ParallaxPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        double delta = 0;
        if (controller.position.haveDimensions) {
          delta = (controller.page ?? index.toDouble()) - index;
        }
        final absDelta = delta.abs().clamp(0.0, 1.0);
        final scale = 1 - (absDelta * 0.06);
        final opacity = 1 - (absDelta * 0.4);
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════
//  Keep pages alive across PageView scrolls (preserves
//  feed state, scroll position, realtime channels, etc).
// ════════════════════════════════════════════════════
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ════════════════════════════════════════════════════
//  Nav button (unchanged behavior, kept from before)
// ════════════════════════════════════════════════════
class _NavButton extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounce = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
    ]).animate(_bounceController);
  }

  @override
  void didUpdateWidget(covariant _NavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _bounceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.red : Colors.grey.shade600;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(24),
      splashColor: AppColors.red.withOpacity(0.08),
      highlightColor: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _bounce,
          builder: (context, child) =>
              Transform.scale(scale: _bounce.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active
                  ? AppColors.red.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: SizedBox(
                key: ValueKey('${widget.item.filled}-${widget.active}'),
                width: 26,
                height: 26,
                child: SvgPicture.asset(
                  widget.active ? widget.item.filled : widget.item.outline,
                  width: 26,
                  height: 26,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
              ),
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
