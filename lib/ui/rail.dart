import 'package:flutter/material.dart';

import '../theme.dart';

const railWidth = 64.0;

/// The slim left rail every screen carries instead of a top bar: mark or
/// back button on top, the screen's name written up the middle, controls at
/// the bottom. The rest of the screen belongs to the photo.
class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.leading, required this.label, this.bottom = const []});

  final Widget leading;
  final String label;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Container(
      width: railWidth + pad.left,
      color: Tone.black,
      padding: EdgeInsets.only(left: pad.left, top: pad.top + 14, bottom: pad.bottom + 14),
      child: Column(
        children: [
          SizedBox(height: 48, child: Center(child: leading)),
          const SizedBox(height: 18),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(label.toUpperCase(), style: syne(22, color: Tone.bone), maxLines: 1),
              ),
            ),
          ),
          for (final b in bottom) Padding(padding: const EdgeInsets.only(top: 6), child: b),
        ],
      ),
    );
  }
}

/// A square rail button. Flat, no ripple glow; an active state only swaps ink.
class RailButton extends StatelessWidget {
  const RailButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: railWidth,
              height: 52,
              child: Icon(icon, size: 24, color: onTap == null ? Tone.faint : (active ? Tone.gold : Tone.bone)),
            ),
          ),
        ),
      );
}

class RailBack extends StatelessWidget {
  const RailBack({super.key});

  @override
  Widget build(BuildContext context) =>
      RailButton(icon: Icons.arrow_back, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop());
}
