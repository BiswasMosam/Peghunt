import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peghunt/data/app_state.dart';
import 'package:peghunt/scan/matcher.dart';
import 'package:peghunt/scan/scanner.dart';
import 'package:peghunt/theme.dart';
import 'package:peghunt/ui/book_screen.dart';
import 'package:peghunt/ui/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for ML Kit: returns fixed lines, remembers it was closed.
class FakeOcr implements OcrEngine {
  FakeOcr(this.lines);
  final List<OcrLine> lines;
  var closed = false;

  @override
  Future<List<OcrLine>> read(String imagePath) async => lines;

  @override
  Future<void> close() async => closed = true;
}

const fixture = 'test/fixtures/wall_300x400.jpg';

Widget app(Widget home) => MaterialApp(theme: peghuntTheme(), home: home);

Future<void> settle(WidgetTester tester) async {
  // Image decoding happens off the fake clock.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

void main() {
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await AppState.load();
  });

  testWidgets('result screen rings what the OCR read and lists it', (tester) async {
    final ocr = FakeOcr([
      const OcrLine('SUBARU IMPREZA', Rect.fromLTWH(200, 50, 80, 15)),
      const OcrLine('HW J-IMPORTS 7/10', Rect.fromLTWH(200, 70, 90, 15)),
      const OcrLine("'87 BUICK REGAL GNX", Rect.fromLTWH(180, 250, 110, 15)),
      const OcrLine('FORD ESCORT', Rect.fromLTWH(20, 50, 70, 15)),
    ]);
    await tester.pumpWidget(app(ResultScreen(imagePath: fixture, state: state, scanner: () => Scanner(ocr))));
    await settle(tester);

    expect(find.text('2 SPOTTED'), findsOneWidget);
    expect(find.text('Subaru Impreza'), findsOneWidget);
    expect(find.text("'87 Buick Regal GNX"), findsOneWidget);
    expect(find.text('LIKELY'), findsOneWidget);
    expect(find.text('POSSIBLE'), findsOneWidget);
    expect(ocr.closed, isTrue);

    // First tap on a row flies to the card, the second opens what to check.
    await tester.tap(find.text('Subaru Impreza'));
    await tester.pumpAndSettle();
    expect(find.text('SHOW ALL'), findsOneWidget);
    expect(find.text('CHECK BEFORE YOU BUY'), findsNothing);
    await tester.tap(find.text('Subaru Impreza'));
    await tester.pumpAndSettle();
    expect(find.text('CHECK BEFORE YOU BUY'), findsOneWidget);
    expect(find.text('Super Treasure Hunt'), findsOneWidget);
  });

  testWidgets('marking a car found from the sheet shows in the book', (tester) async {
    final ocr = FakeOcr([const OcrLine('SUBARU IMPREZA', Rect.fromLTWH(200, 50, 80, 15))]);
    await tester.pumpWidget(app(ResultScreen(imagePath: fixture, state: state, scanner: () => Scanner(ocr))));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Mark as found'));
    await tester.pumpAndSettle();
    expect(state.isFound(state.book.byId('2026-sth-176')!), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('found'), ['2026-sth-176']);
  });

  testWidgets('nothing found says how many cards were read', (tester) async {
    final ocr = FakeOcr([
      const OcrLine('123/250', Rect.fromLTWH(20, 50, 60, 15)),
      const OcrLine('088/250', Rect.fromLTWH(200, 50, 60, 15)),
    ]);
    await tester.pumpWidget(app(ResultScreen(imagePath: fixture, state: state, scanner: () => Scanner(ocr))));
    await settle(tester);
    expect(find.text('NOTHING'), findsOneWidget);
    expect(find.text('Nothing on the list.'), findsOneWidget);
    expect(find.textContaining('READ 2 CARDS'), findsOneWidget);
  });

  testWidgets('an OCR failure is shown, not swallowed', (tester) async {
    await tester.pumpWidget(app(ResultScreen(imagePath: fixture, state: state, scanner: () => Scanner(_BrokenOcr()))));
    await settle(tester);
    expect(find.text('Could not read this photo.'), findsOneWidget);
  });

  testWidgets('book: years switch, found count, last scan year stays on', (tester) async {
    await tester.pumpWidget(app(BookScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('0 OF 30 FOUND'), findsOneWidget);
    expect(find.text('Drift Ender'), findsOneWidget);

    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    expect(find.text("'87 Audi Quattro"), findsOneWidget);

    // Turn 2025 and 2024 off; 2026 is then the only year and cannot go.
    await tester.tap(find.bySemanticsLabel('Check 2025 cars when scanning'));
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Check 2024 cars when scanning'));
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Check 2026 cars when scanning'));
    await tester.pumpAndSettle();
    expect(state.scanYears, {2026});
    expect(find.text('SCANS CHECK 2026 (THE ONLY YEAR ON)'), findsOneWidget);
  });
}

class _BrokenOcr implements OcrEngine {
  @override
  Future<List<OcrLine>> read(String imagePath) => Future.error(StateError('ML Kit fell over'));

  @override
  Future<void> close() async {}
}
