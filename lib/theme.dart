import 'package:flutter/material.dart';

import 'data/hunt_book.dart';

/// Peghunt's whole identity is one ring on a wall of pegs. The ring colours
/// are the colours of the flame printed behind a hunted car (gold for a
/// Super Treasure Hunt, silver for a Treasure Hunt) plus red for a chase.
/// They are the only colours in the app. Everything else is flat ink on black.
abstract final class Tone {
  static const black = Color(0xFF0B0B0C);
  static const raised = Color(0xFF151517);
  static const line = Color(0xFF26262A);
  static const bone = Color(0xFFF2F0EA);
  static const dim = Color(0xFF8D8D93);
  static const faint = Color(0xFF4A4A50);

  static const gold = Color(0xFFE8B649);
  static const silver = Color(0xFFC9CFD8);
  static const red = Color(0xFFFF5A4E);

  static Color of(HuntKind k) => switch (k) {
        HuntKind.sth => gold,
        HuntKind.th => silver,
        HuntKind.chase => red,
      };
}

/// Manrope ships as one variable font, so its weight has to be set on the
/// wght axis as well as on fontWeight.
TextStyle manrope(double size, {FontWeight weight = FontWeight.w500, Color color = Tone.bone, double? height}) =>
    TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height,
    );

/// Syne for display words only: the wordmark, screen names, big counts.
TextStyle syne(double size, {FontWeight weight = FontWeight.w800, Color color = Tone.bone, double? height}) => TextStyle(
      fontFamily: 'Syne',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height ?? 1.0,
      letterSpacing: -0.5,
    );

/// Space Mono for anything printed on a card: numbers, case letters, labels.
TextStyle mono(double size, {bool bold = false, Color color = Tone.dim, double letterSpacing = 1.2}) => TextStyle(
      fontFamily: 'SpaceMono',
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      letterSpacing: letterSpacing,
    );

ThemeData peghuntTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Tone.black,
    canvasColor: Tone.black,
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      surface: Tone.black,
      primary: Tone.bone,
      onPrimary: Tone.black,
      secondary: Tone.gold,
      onSurface: Tone.bone,
      outline: Tone.line,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Manrope', bodyColor: Tone.bone, displayColor: Tone.bone),
    dividerColor: Tone.line,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tone.raised,
      modalBackgroundColor: Tone.raised,
      shape: RoundedRectangleBorder(),
      showDragHandle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tone.bone,
      contentTextStyle: manrope(14, weight: FontWeight.w600, color: Tone.black),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
    ),
  );
}
