import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hunt_book.dart';

/// The hunt book plus the two things the collector decides: which cars they
/// have found, and which years' lists a scan checks against.
class AppState extends ChangeNotifier {
  AppState._(this.book, this._prefs, this._found, this._years);

  final HuntBook book;
  final SharedPreferences _prefs;
  final Set<String> _found;
  final Set<int> _years;

  static const _foundKey = 'found';
  static const _yearsKey = 'scanYears';

  static Future<AppState> load() async {
    final book = HuntBook.fromJsonString(
      await rootBundle.loadString('assets/hunts.json'),
      castings: await rootBundle.loadString('assets/castings.json'),
    );
    final prefs = await SharedPreferences.getInstance();
    final found = (prefs.getStringList(_foundKey) ?? const []).toSet();
    final saved = prefs.getStringList(_yearsKey)?.map(int.tryParse).whereType<int>().toSet();
    final years = (saved == null || saved.isEmpty) ? book.years.toSet() : saved.intersection(book.years.toSet());
    return AppState._(book, prefs, found, years.isEmpty ? book.years.toSet() : years);
  }

  Set<int> get scanYears => Set.unmodifiable(_years);

  bool isFound(HuntEntry e) => _found.contains(e.id);

  int foundIn(int year) => book.forYear(year).where(isFound).length;

  Future<void> setFound(HuntEntry e, bool found) async {
    found ? _found.add(e.id) : _found.remove(e.id);
    notifyListeners();
    await _prefs.setStringList(_foundKey, _found.toList()..sort());
  }

  /// At least one year always stays on, or a scan could never find anything.
  Future<void> toggleScanYear(int year) async {
    if (_years.contains(year)) {
      if (_years.length == 1) return;
      _years.remove(year);
    } else {
      _years.add(year);
    }
    notifyListeners();
    await _prefs.setStringList(_yearsKey, [for (final y in _years) '$y']);
  }
}
