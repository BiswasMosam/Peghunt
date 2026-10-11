import 'package:flutter/material.dart';

import '../theme.dart';

/// A car in the book is marked found the way the camera marks a hit: an
/// empty ring that fills in.
class FoundRing extends StatelessWidget {
  const FoundRing({super.key, required this.found, required this.color, required this.onTap});
  final bool found;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: found,
        label: found ? 'Found. Tap to unmark' : 'Mark as found',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: found ? color : Colors.transparent,
                  border: Border.all(color: found ? color : Tone.faint, width: 2),
                ),
                child: found ? const Icon(Icons.check, size: 16, color: Tone.black) : null,
              ),
            ),
          ),
        ),
      );
}
