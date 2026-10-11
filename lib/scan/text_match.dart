/// Text helpers for matching what OCR read off a card against the hunt book.
///
/// OCR on a photo of a peg wall is noisy: letters swap for digits, accents
/// vanish, apostrophes come and go. Everything here is about comparing two
/// strings the way a person squinting at a card would.
library;

const _accents = {
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
  'Ñ': 'N', 'Ç': 'C',
};

/// Upper case, accents folded, apostrophes dropped ('64 and 64 are the same
/// car), everything else that is not a letter or digit turned into a space.
String normalize(String s) {
  final up = s.toUpperCase();
  final b = StringBuffer();
  for (final ch in up.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"['’‘`´]"), '')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();
}

List<String> tokenize(String s) {
  final n = normalize(s);
  return n.isEmpty ? const [] : n.split(' ');
}

/// Words too common on Hot Wheels cards to identify a car by themselves.
const stopWords = {
  'HW', 'HOT', 'WHEELS', 'THE', 'AND', 'CUSTOM', 'FORD', 'CHEVY', 'CHEVROLET',
  'HONDA', 'NISSAN', 'TOYOTA', 'DODGE', 'PORSCHE', 'FERRARI', 'BMW', 'AUDI',
  'MAZDA', 'RACE', 'RACING', 'CAR', 'SUPER', 'SPORT', 'MODEL', 'DRIFT', 'TYPE',
  'EDITION', 'SERIES', 'NEW',
};

bool _isDigits(String t) => RegExp(r'^[0-9]+$').hasMatch(t);

/// The tokens of a car or series name that a card must show for a match.
/// Single letters are dropped (OCR loses them, and "2 Jet Z" still reads
/// as 2 JET); single digits are kept because '64 Impala is not '59 Impala.
List<String> requiredTokens(String name) =>
    [for (final t in tokenize(name)) if (t.length >= 2 || _isDigits(t)) t];

/// True when the name has at least one word that identifies the car on its
/// own. "Custom Otto" has OTTO; "2 Jet Z" has nothing, so it is only ever
/// matched through its collector number.
bool hasDistinctiveToken(List<String> tokens) =>
    tokens.any((t) => t.length >= 4 && !_isDigits(t) && !stopWords.contains(t));

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// How many letters OCR may get wrong in a word of this length.
int _slack(String t) => _isDigits(t) ? 0 : t.length >= 9 ? 2 : t.length >= 5 ? 1 : 0;

bool tokenSeen(String want, List<String> seen) {
  final slack = _slack(want);
  for (final s in seen) {
    if (s == want) return true;
    if (slack > 0 && (s.length - want.length).abs() <= slack && levenshtein(s, want) <= slack) {
      return true;
    }
  }
  return false;
}

/// Every required token of [wanted] shows up in [seen].
bool allTokensSeen(List<String> wanted, List<String> seen) =>
    wanted.isNotEmpty && wanted.every((w) => tokenSeen(w, seen));

const _letterLookalikes = {'0': 'O', '1': 'I', '5': 'S', '8': 'B', '2': 'Z', '6': 'G'};

/// A name boiled down to what OCR reliably keeps: letters and digits, no
/// spaces, and the digits that look like letters turned into those letters.
/// OCR splits words ("BEN TLEY") and joins them ("20TOYOT"), and reads
/// DODGER as D00GER; none of that changes the skeleton by much.
String skeleton(String s) {
  final b = StringBuffer();
  for (final ch in normalize(s).split('')) {
    if (ch == ' ') continue;
    b.write(_letterLookalikes[ch] ?? ch);
  }
  return b.toString();
}

final _yearToken = RegExp(r"(^|\s)(['’]\d{2}|(19|20)\d{2})(?=\s|$)");

/// The skeletons a car's name may show up as. Bilingual cards put the
/// French in the middle of the name, so "Ford Model A Custom '31" reads
/// "FORD MODEL A CUSTOM / PERSONNALISÉ '31". A long name therefore also
/// counts without its year. A short one keeps it: '64 Impala without the
/// '64 is every Impala.
List<String> nameKeys(String name) {
  final full = skeleton(name);
  final core = skeleton(name.replaceAll(_yearToken, ' '));
  return core != full && core.length >= 12 ? [full, core] : [full];
}

/// How many wrong letters a name of this skeleton length may have and
/// still count. Real shop photos read FORD MODEL A CUSTOM as FORD MOOL A
/// CUSTOV: three letters off. Near misses like SWEET DRIVER and SPEED
/// DRIVER are kept apart by matching against every ordinary car too, so
/// the closer name wins.
int errorBudget(int length) => length < 6 ? 0 : length < 10 ? 1 : length < 16 ? 2 : 3;

/// Fewest edits that turn [pattern] into some stretch of [text], or null if
/// it would take more than [maxErrors]. Stops as soon as no stretch can
/// still make it, which is after a row or two for most names.
int? fuzzyFind(String pattern, String text, int maxErrors) {
  final m = pattern.length, n = text.length;
  if (m == 0 || n < m - maxErrors) return null;
  var prev = List<int>.filled(n + 1, 0);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    cur[0] = i;
    var rowMin = i;
    final p = pattern.codeUnitAt(i - 1);
    for (var j = 1; j <= n; j++) {
      final sub = prev[j - 1] + (p == text.codeUnitAt(j - 1) ? 0 : 1);
      final del = prev[j] + 1, ins = cur[j - 1] + 1;
      final v = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > maxErrors) return null;
    final t = prev;
    prev = cur;
    cur = t;
  }
  var best = prev[0];
  for (var j = 1; j <= n; j++) {
    if (prev[j] < best) best = prev[j];
  }
  return best <= maxErrors ? best : null;
}

const _digitLookalikes = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', '|': '1', 'S': '5', 'B': '8', 'Z': '2'};

/// Reads a number OCR may have mangled ("1O7" is 107, "2S0" is 250).
int? readDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.toUpperCase().split('')) {
    final d = _digitLookalikes[ch] ?? ch;
    if (!RegExp(r'[0-9]').hasMatch(d)) return null;
    b.write(d);
  }
  return b.isEmpty ? null : int.tryParse(b.toString());
}

// The 250 is often read as 260 or 2S0.
final _collectorRe = RegExp(r'(?<![0-9A-Z])([0-9OQDILSBZ|]{1,3})\s*[/\\|]\s*([2Z][56S][0OQD])(?![0-9])');

/// Collector numbers in a line of card text: "176/250" gives 176.
List<int> collectorNumbers(String line) {
  final out = <int>[];
  for (final m in _collectorRe.allMatches(line.toUpperCase())) {
    final n = readDigits(m.group(1)!);
    if (n != null && n >= 1 && n <= 250) out.add(n);
  }
  return out;
}

final _seriesRe = RegExp(r'(?<![0-9A-Z/])([0-9OQD]{1,2})\s*/\s*([0-9]{1,2})(?![0-9])');

/// Premium chase cars are numbered zero in their set: "0/5" instead of
/// "1/5". True when a line carries one of those.
bool hasChaseNumber(String line) {
  for (final m in _seriesRe.allMatches(line.toUpperCase())) {
    final top = readDigits(m.group(1)!);
    final bottom = int.tryParse(m.group(2)!);
    if (top == 0 && bottom != null && bottom >= 3 && bottom <= 12) return true;
  }
  return false;
}

/// The back of a Treasure Hunt card says so: "Congratulations! This symbol
/// means you just found a collectible treasure-hunt vehicle!"
({bool th, bool sth}) treasurePhrase(List<String> seen) {
  final treasure = tokenSeen('TREASURE', seen);
  final hunt = seen.contains('HUNT');
  final congrats = tokenSeen('CONGRATULATIONS', seen) && tokenSeen('SYMBOL', seen);
  final th = (treasure && hunt) || congrats;
  return (th: th, sth: th && seen.contains('SUPER'));
}
