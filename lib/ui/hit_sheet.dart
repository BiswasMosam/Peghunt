import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/hunt_book.dart';
import '../scan/matcher.dart';
import '../theme.dart';
import 'found_ring.dart';

Future<void> showHitSheet(BuildContext context, Hit hit, AppState state) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HitSheet(hit: hit, state: state),
    );

/// What a ring means and what to check on the card before paying for it.
class HitSheet extends StatelessWidget {
  const HitSheet({super.key, required this.hit, required this.state});
  final Hit hit;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = Tone.of(hit.kind);
    final shown = hit.candidates.take(3).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: color, width: 3))),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_certaintyLine, style: mono(11, bold: true, color: color)),
              const SizedBox(height: 10),
              Text(hit.kind.label, style: syne(32, color: color, height: 1.05)),
              if (hit.kind == HuntKind.sth && hit.certainty != Certainty.confirmed) ...[
                const SizedBox(height: 10),
                Text(
                  'The regular car carries the same number on the same card. Only the details below tell the Super apart.',
                  style: manrope(14, color: Tone.dim, height: 1.45),
                ),
              ],
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 22),
                for (final e in shown) _Candidate(entry: e, state: state),
                if (hit.candidates.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('+${hit.candidates.length - shown.length} MORE WITH THIS NUMBER', style: mono(10)),
                  ),
              ],
              const SizedBox(height: 24),
              Text('CHECK BEFORE YOU BUY', style: mono(11, bold: true, color: Tone.bone)),
              const SizedBox(height: 10),
              for (final c in _checks(hit)) _Check(text: c, color: color),
              const SizedBox(height: 22),
              Text('READ OFF THE CARD', style: mono(11, bold: true, color: Tone.bone)),
              const SizedBox(height: 8),
              for (final e in hit.evidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(e, style: mono(11)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _certaintyLine => switch (hit.certainty) {
        Certainty.confirmed => 'CONFIRMED BY THE CARD',
        Certainty.likely => 'LIKELY: TWO THINGS ON THE CARD AGREE',
        Certainty.possible => 'POSSIBLE: ONE THING MATCHED',
      };

  static List<String> _checks(Hit hit) {
    final first = hit.candidates.isEmpty ? null : hit.candidates.first;
    if (hit.kind == HuntKind.chase && first != null) {
      if (first.twin) {
        return [
          'Same card and set number as the regular car: only the paint tells them apart',
          'Spectraflame paint${first.color != null ? ', ${first.color}' : ''}: deep, glossy, almost liquid',
          'One per case, so most cards on the peg are the regular car',
        ];
      }
      return [
        'Set number ${first.slot} printed on the card${first.slot == '0/5' ? ', not 1/5 to 5/5' : ''}',
        if (first.color != null) '${first.color} paint, unlike the regular car of the set',
        'Real Riders rubber tires',
      ];
    }
    return _kindChecks(hit.kind);
  }

  static List<String> _kindChecks(HuntKind k) => switch (k) {
        HuntKind.sth => const [
            'Gold circle flame printed on the card, behind the car',
            'Spectraflame paint: deep, glossy, almost liquid',
            'Real Riders: rubber tires, not plastic',
            'A small TH printed on the car',
          ],
        HuntKind.th => const [
            'Silver circle flame printed on the card, behind the car',
            'Circle flame logo printed on the car',
            'Card back: "This symbol means you just found a treasure hunt vehicle"',
          ],
        HuntKind.chase => const [
            'A 0 in the set number on the card, like 0/5',
            'Often black or a colour none of the set has',
            'Real Riders rubber tires',
          ],
      };
}

class _Candidate extends StatelessWidget {
  const _Candidate({required this.entry, required this.state});
  final HuntEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final meta = [
      '${entry.year}',
      if (entry.caseLetter != null) 'CASE ${entry.caseLetter}',
      if (entry.isChase) (entry.line ?? '').toUpperCase() else entry.numberLabel,
      if (entry.isChase && entry.slot != null) entry.slot!,
    ].join('  ·  ');
    final detail = [
      entry.series + (entry.seriesNumber != null ? ' #${entry.seriesNumber}' : ''),
      if (entry.color != null) entry.color!,
    ].join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tone.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: manrope(18, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(meta, style: mono(11, color: Tone.bone)),
                const SizedBox(height: 2),
                Text(detail, style: manrope(13, color: Tone.dim)),
                if (entry.note != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.note!, style: manrope(12, color: Tone.dim)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: state,
            builder: (_, _) => FoundRing(
              found: state.isFound(entry),
              color: Tone.of(entry.kind),
              onTap: () => state.setFound(entry, !state.isFound(entry)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: manrope(15, height: 1.4))),
          ],
        ),
      );
}
