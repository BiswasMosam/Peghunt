import 'dart:convert';

/// The three kinds of car Peghunt looks for, rarest first.
enum HuntKind {
  sth('STH', 'Super Treasure Hunt'),
  th('TH', 'Treasure Hunt'),
  chase('CHASE', 'Chase');

  const HuntKind(this.short, this.label);
  final String short;
  final String label;

  static HuntKind parse(String s) =>
      values.firstWhere((k) => k.name == s, orElse: () => throw FormatException('Unknown kind "$s"'));
}

/// One car from a year's hunt list: a mainline Treasure Hunt or Super
/// Treasure Hunt, or a premium chase.
class HuntEntry {
  const HuntEntry({
    required this.year,
    required this.kind,
    required this.name,
    required this.series,
    this.caseLetter,
    this.number,
    this.seriesNumber,
    this.color,
    this.note,
    this.line,
    this.slot,
    this.twin = false,
  });

  final int year;
  final HuntKind kind;
  final String name;

  /// The mainline series ("HW J-Imports"), or for a chase the set printed
  /// on the card ("Hammer Drop").
  final String series;
  final String? caseLetter;

  /// Collector number in the year's mainline, the "176" of "176/250".
  /// Premium chases have none.
  final int? number;
  final int? seriesNumber;
  final String? color;
  final String? note;

  /// For a chase: the premium line ("Car Culture", "Fast & Furious").
  final String? line;

  /// For a chase: its place in the set as printed, "0/5" for a Car Culture
  /// chase, "6/6" where the last car is the chase.
  final String? slot;

  /// A chase that shares its card and set number with a regular car and
  /// differs only in paint, like a Super Treasure Hunt.
  final bool twin;

  bool get isChase => kind == HuntKind.chase;

  String get id => isChase
      ? '$year-chase-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}'
      : '$year-${kind.name}-$number';

  /// "176/250", the way it is printed on the card.
  String get numberLabel => number == null ? '' : '${number.toString().padLeft(3, '0')}/250';

  factory HuntEntry.fromJson(int year, Map<String, dynamic> j) => HuntEntry(
        year: year,
        kind: HuntKind.parse(j['kind'] as String),
        caseLetter: j['case'] as String?,
        number: j['number'] as int?,
        name: j['name'] as String,
        series: (j['series'] ?? j['set']) as String,
        seriesNumber: j['seriesNumber'] as int?,
        color: j['color'] as String?,
        note: j['note'] as String?,
        line: j['line'] as String?,
        slot: j['slot'] as String?,
        twin: j['twin'] as bool? ?? false,
      );

  @override
  String toString() => isChase ? '$year CHASE ${slot ?? 'twin'} $name' : '$year ${kind.short} #$number $name';
}

/// One car of a year's mainline, hunted or not.
class Casting {
  const Casting(this.year, this.number, this.name, this.series);
  final int year;
  final int number;
  final String name;
  final String series;
}

/// Every year's hunt list (assets/hunts.json), plus every car of those
/// years' mainline (assets/castings.json). The full lists are what stop an
/// ordinary 2026 Bone Shaker from being taken for the 2024 Treasure Hunt.
class HuntBook {
  HuntBook(this.entries, {required this.updated, required this.sources, this.castings = const []});

  final List<HuntEntry> entries;
  final String updated;
  final List<String> sources;
  final List<Casting> castings;

  factory HuntBook.fromJsonString(String raw, {String? castings}) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final years = j['years'] as Map<String, dynamic>;
    final entries = <HuntEntry>[
      for (final y in years.entries)
        for (final e in y.value as List) HuntEntry.fromJson(int.parse(y.key), e as Map<String, dynamic>),
    ];
    return HuntBook(
      entries,
      updated: j['updated'] as String,
      sources: [for (final s in j['sources'] as List) s as String],
      castings: castings == null ? const [] : _castings(castings),
    );
  }

  static List<Casting> _castings(String raw) {
    final years = (jsonDecode(raw) as Map<String, dynamic>)['years'] as Map<String, dynamic>;
    return [
      for (final y in years.entries)
        for (final row in y.value as List)
          Casting(int.parse(y.key), (row as List)[0] as int, row[1] as String, row[2] as String),
    ];
  }

  /// Newest year first.
  List<int> get years => (entries.map((e) => e.year).toSet().toList()..sort()).reversed.toList();

  List<HuntEntry> forYear(int year) => [for (final e in entries) if (e.year == year) e];

  HuntEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}
