import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kBg = Color(0xFF0B0B1A);
const kCard = Color(0xFF16162B);
const kPink = Color(0xFFFF2D75);
const kPurple = Color(0xFF7B2FF7);
const kOrange = Color(0xFFFF8A00);
const kGradient = LinearGradient(
  colors: [kPink, kPurple],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(primary: kPink, secondary: kPurple, surface: kCard),
    textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0, centerTitle: true),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kCard),
  );
}
