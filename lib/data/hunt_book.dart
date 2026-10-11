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

/// One car from a year's Treasure Hunt / Super Treasure Hunt list.
class HuntEntry {
  const HuntEntry({
    required this.year,
    required this.kind,
    required this.caseLetter,
    required this.number,
    required this.name,
    required this.series,
    this.seriesNumber,
    this.color,
    this.note,
  });

  final int year;
  final HuntKind kind;
  final String caseLetter;

  /// Collector number in the year's mainline, the "176" of "176/250".
  final int number;
  final String name;
  final String series;
  final int? seriesNumber;
  final String? color;
  final String? note;

  String get id => '$year-${kind.name}-$number';

  /// "176/250", the way it is printed on the card.
  String get numberLabel => '${number.toString().padLeft(3, '0')}/250';

  factory HuntEntry.fromJson(int year, Map<String, dynamic> j) => HuntEntry(
        year: year,
        kind: HuntKind.parse(j['kind'] as String),
        caseLetter: j['case'] as String,
        number: j['number'] as int,
        name: j['name'] as String,
        series: j['series'] as String,
        seriesNumber: j['seriesNumber'] as int?,
        color: j['color'] as String?,
        note: j['note'] as String?,
      );

  @override
  String toString() => '$year ${kind.short} #$number $name';
}

/// Every year's list, bundled with the app as assets/hunts.json.
class HuntBook {
  HuntBook(this.entries, {required this.updated, required this.sources});

  final List<HuntEntry> entries;
  final String updated;
  final List<String> sources;

  factory HuntBook.fromJsonString(String raw) {
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
    );
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
