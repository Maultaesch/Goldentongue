import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const black = Color(0xFF000000);
  static const charcoal = Color(0xFF111111);
  static const card = Color(0xFF1A1A1A);
  static const gold = Color(0xFFD4AF37);
  static const goldPremium = Color(0xFFFFD700);
  static const goldAccent = Color(0xFFC9A227);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8B8B8);
  static const success = Color(0xFF00C853);
  static const line = Color(0xFF2B2B2B);
  static const glow = Color(0x24D4AF37);

  static const goldGradient = LinearGradient(
    colors: [goldAccent, goldPremium, goldAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final body = GoogleFonts.manropeTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text);
    TextStyle serif(double size, {Color color = AppColors.text}) =>
        GoogleFonts.cormorantGaramond(
            fontSize: size, fontWeight: FontWeight.w600, color: color, height: 1.1);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.black,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.goldAccent,
        surface: AppColors.card,
        onPrimary: Colors.black,
      ),
      textTheme: body.copyWith(
        headlineLarge: serif(34),
        headlineMedium: serif(24),
        titleLarge: serif(22),
        displayMedium: serif(40, color: AppColors.gold),
        bodySmall: body.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.charcoal,
        indicatorColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11,
              color: s.contains(WidgetState.selected)
                  ? AppColors.goldPremium
                  : AppColors.textSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? AppColors.goldPremium
                  : AppColors.textSecondary,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.charcoal,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.goldPremium,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.gold,
        dividerColor: AppColors.line,
        tabAlignment: TabAlignment.start,
      ),
    );
  }
}
