import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/hunt_book.dart';
import '../theme.dart';
import 'found_ring.dart';
import 'rail.dart';

/// Every year's Treasure Hunts and Super Treasure Hunts, with a ring to tick
/// off the ones already found.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.state});
  final AppState state;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  late int _year = widget.state.book.years.first;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      body: Row(
        children: [
          const SideRail(leading: RailBack(), label: 'Hunt book'),
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => _list(context, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, AppState state) {
    final pad = MediaQuery.paddingOf(context);
    final cars = state.book.forYear(_year);
    final sth = [for (final e in cars) if (e.kind == HuntKind.sth) e];
    final th = [for (final e in cars) if (e.kind == HuntKind.th) e];
    final chase = [for (final e in cars) if (e.kind == HuntKind.chase) e];
    final scanning = state.scanYears.contains(_year);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, pad.top + 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final y in state.book.years)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _year = y),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('$y', style: syne(40, color: y == _year ? Tone.bone : Tone.faint)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('${state.foundIn(_year)} OF ${cars.length} FOUND', style: mono(12, bold: true, color: Tone.bone)),
                const SizedBox(height: 14),
                _ScanToggle(
                  on: scanning,
                  year: _year,
                  locked: scanning && state.scanYears.length == 1,
                  onTap: () => state.toggleScanYear(_year),
                ),
              ],
            ),
          ),
        ),
        _section('SUPER TREASURE HUNTS', HuntKind.sth, sth, state),
        _section('TREASURE HUNTS', HuntKind.th, th, state),
        if (chase.isNotEmpty) _section('CHASE CARS', HuntKind.chase, chase, state),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 28, 20, pad.bottom + 28),
          sliver: SliverToBoxAdapter(child: _Credits(book: state.book)),
        ),
      ],
    );
  }

  Widget _section(String title, HuntKind kind, List<HuntEntry> cars, AppState state) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 30, 8, 0),
        sliver: SliverList.list(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title, style: mono(11, bold: true, color: Tone.of(kind))),
            ),
            for (final e in cars) _Row(entry: e, state: state),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.state});
  final HuntEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final found = state.isFound(entry);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tone.line))),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: entry.isChase
                ? Text(entry.slot ?? 'TWIN',
                    style: mono(entry.slot == null ? 8 : 11, bold: true, color: found ? Tone.of(entry.kind) : Tone.faint))
                : Text(entry.caseLetter ?? '', style: syne(22, color: found ? Tone.of(entry.kind) : Tone.faint)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: manrope(15, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry.isChase) entry.line ?? '' else entry.numberLabel,
                    entry.series,
                    if (entry.color != null) entry.color!,
                  ].join('  ·  '),
                  style: mono(10),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          FoundRing(
            found: found,
            color: Tone.of(entry.kind),
            onTap: () => state.setFound(entry, !found),
          ),
        ],
      ),
    );
  }
}

class _ScanToggle extends StatelessWidget {
  const _ScanToggle({required this.on, required this.year, required this.locked, required this.onTap});
  final bool on;
  final int year;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: on,
        button: true,
        excludeSemantics: true,
        label: 'Check $year cars when scanning',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: locked ? null : onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 22,
                padding: const EdgeInsets.all(3),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: on ? Tone.bone : Colors.transparent,
                  border: Border.all(color: on ? Tone.bone : Tone.faint, width: 1.5),
                ),
                child: Container(width: 14, height: 14, color: on ? Tone.black : Tone.faint),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  locked ? 'SCANS CHECK $year (THE ONLY YEAR ON)' : 'SCANS CHECK $year CARDS',
                  style: mono(11, color: on ? Tone.bone : Tone.dim),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Credits extends StatelessWidget {
  const _Credits({required this.book});
  final HuntBook book;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LISTS UPDATED ${book.updated}', style: mono(10, color: Tone.bone)),
          const SizedBox(height: 8),
          Text(
            'Compiled from collector checklists: ${book.sources.join('; ')}. '
            'Where they disagree it says so on the car. Always check the car itself before you pay.',
            style: manrope(12, color: Tone.dim, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Peghunt is a fan project. It is not made by, endorsed by or affiliated with Mattel. '
            'Hot Wheels and Treasure Hunt are trademarks of Mattel, Inc.',
            style: manrope(12, color: Tone.dim, height: 1.5),
          ),
        ],
      );
}
