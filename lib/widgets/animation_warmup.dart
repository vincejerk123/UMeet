import 'package:flutter/material.dart';

/// Renders an off-screen, invisible copy of the app's core animations
/// once on cold start. Compiles GPU shaders ahead of time so the first
/// real animation plays smoothly.
///
/// Place this as a sibling of the real UI (e.g. in `Stack` on the
/// login screen). It disposes itself after completing once.
class AnimationWarmup extends StatefulWidget {
  const AnimationWarmup({super.key});

  @override
  State<AnimationWarmup> createState() => _AnimationWarmupState();
}

class _AnimationWarmupState extends State<AnimationWarmup>
    with TickerProviderStateMixin {
  late AnimationController _c1;
  late AnimationController _c2;
  late AnimationController _c3;
  late AnimationController _c4;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _c2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _c3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _c4 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _runAll();
  }

  Future<void> _runAll() async {
    // Give the first frame time to settle before warming up
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // Run each animation sequentially (each compiles its own shader pass)
    await _c1.forward(from: 0);
    if (!mounted) return;
    await _c2.forward(from: 0);
    if (!mounted) return;
    await _c3.forward(from: 0);
    if (!mounted) return;
    await _c4.forward(from: 0);

    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    _c4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once done, collapse to zero size — no cost after startup
    if (_done) return const SizedBox.shrink();

    // Off-screen and invisible (opacity 0 + IgnorePointer)
    return Positioned(
      left: -1000,
      top: -1000,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.0,
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              children: [
                // 1) Fade + slide (page transitions)
                AnimatedBuilder(
                  animation: _c1,
                  builder: (_, __) => Transform.translate(
                    offset: Offset((1 - _c1.value) * 40, 0),
                    child: Opacity(
                      opacity: _c1.value,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
                // 2) Scale (heart pop, bounce)
                AnimatedBuilder(
                  animation: _c2,
                  builder: (_, __) => Transform.scale(
                    scale: 0.5 + (_c2.value * 0.5),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 3) Fade scale (image viewer)
                AnimatedBuilder(
                  animation: _c3,
                  builder: (_, __) => Opacity(
                    opacity: _c3.value,
                    child: Transform.scale(
                      scale: 0.9 + (_c3.value * 0.1),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
                // 4) Scale sequence (TweenSequence-style overshoot)
                AnimatedBuilder(
                  animation: _c4,
                  builder: (_, __) {
                    final t = _c4.value;
                    final scale = t < 0.5
                        ? 1.0 +
                              (t * 0.7) // up
                        : 1.35 - ((t - 0.5) * 0.7); // down
                    return Transform.scale(
                      scale: scale,
                      child: Container(color: Colors.transparent),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
