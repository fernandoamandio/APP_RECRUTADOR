import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta das telas do protótipo: azul = remoto do Brasil, laranja = patrocínio de visto.
class AppColors {
  static const ground = Color(0xFFF5F6F3);
  static const ink = Color(0xFF14181F);
  static const quiet = Color(0xFF4B5260);
  static const line = Color(0xFFE2E4DE);
  static const remote = Color(0xFF1D4ED8);
  static const remoteTint = Color(0xFFE3EAFD);
  static const visa = Color(0xFF9A3412);
  static const visaTint = Color(0xFFFDE8DC);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.remote, surface: AppColors.ground),
    scaffoldBackgroundColor: AppColors.ground,
  );
  final body = GoogleFonts.manropeTextTheme(base.textTheme).apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );
  return base.copyWith(
    textTheme: body.copyWith(
      headlineMedium: GoogleFonts.bricolageGrotesque(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
      headlineSmall: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: const CardTheme(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
  );
}
