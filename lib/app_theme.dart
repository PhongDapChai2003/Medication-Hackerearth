import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const String _themeKey = "selected_theme";

  static const Color ink = Color(0xFF172033);
  static const Color mutedInk = Color(0xFF667085);
  static const Color pageBackground = Color(0xFFF4F7FB);
  static const Color surface = Colors.white;
  static const Color line = Color(0xFFE3EAF3);
  static const double pageMaxWidth = 760;
  static const double formMaxWidth = 680;

  static ValueNotifier<String> currentTheme = ValueNotifier<String>("blue");

  static const List<String> themes = [
    "blue",
    "pink",
    "purple",
    "green",
    "orange",
  ];

  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey) ?? "blue";

    if (themes.contains(savedTheme)) {
      currentTheme.value = savedTheme;
    } else {
      currentTheme.value = "blue";
    }
  }

  static Future<void> changeTheme(String theme) async {
    if (!themes.contains(theme)) {
      return;
    }

    currentTheme.value = theme;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme);
  }

  static Color get primaryColor {
    return colorForTheme(currentTheme.value);
  }

  static Color get themeColor {
    return primaryColor;
  }

  static Color get lightColor {
    return lightColorForTheme(currentTheme.value);
  }

  static Color get softColor {
    return softColorForTheme(currentTheme.value);
  }

  static String get themeName {
    return themeNameForTheme(currentTheme.value);
  }

  static String themeNameForTheme(String theme) {
    switch (theme) {
      case "pink":
        return "Pink";
      case "purple":
        return "Purple";
      case "green":
        return "Green";
      case "orange":
        return "Orange";
      case "blue":
      default:
        return "Blue";
    }
  }

  static Color colorForTheme(String theme) {
    switch (theme) {
      case "pink":
        return const Color(0xFFB85F82);
      case "purple":
        return const Color(0xFF786B9E);
      case "green":
        return const Color(0xFF4F806A);
      case "orange":
        return const Color(0xFFA66D45);
      case "blue":
      default:
        return const Color(0xFF4779A8);
    }
  }

  static Color lightColorForTheme(String theme) {
    switch (theme) {
      case "pink":
        return const Color(0xFFF5E9EE);
      case "purple":
        return const Color(0xFFEEEAF4);
      case "green":
        return const Color(0xFFE7F0EB);
      case "orange":
        return const Color(0xFFF5ECE5);
      case "blue":
      default:
        return const Color(0xFFE7EEF5);
    }
  }

  static Color softColorForTheme(String theme) {
    switch (theme) {
      case "pink":
        return const Color(0xFFFAF7F8);
      case "purple":
        return const Color(0xFFF8F7FA);
      case "green":
        return const Color(0xFFF6F9F7);
      case "orange":
        return const Color(0xFFFAF8F6);
      case "blue":
      default:
        return const Color(0xFFF5F8FA);
    }
  }

  static LinearGradient appBackgroundGradient() {
    return LinearGradient(
      colors: [softColor, pageBackground, const Color(0xFFF7F8FA)],
      stops: const [0.0, 0.38, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static BoxDecoration pageDecoration() {
    return BoxDecoration(gradient: appBackgroundGradient());
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < 380) {
      return const EdgeInsets.fromLTRB(14, 14, 14, 28);
    }

    if (width < 720) {
      return const EdgeInsets.fromLTRB(18, 16, 18, 32);
    }

    return const EdgeInsets.fromLTRB(24, 22, 24, 38);
  }

  static ThemeData buildTheme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ).copyWith(
          primary: primaryColor,
          surface: surface,
          onSurface: ink,
          outline: line,
          surfaceContainerLowest: surface,
          surfaceContainerLow: const Color(0xFFF8FAFC),
          surfaceContainer: const Color(0xFFF2F6FB),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: pageBackground,
      canvasColor: surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(
          color: mutedInk,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primaryColor, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size(48, 50),
          side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: lightColor,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalBarrierColor: Color(0x660F172A),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: ink,
        textColor: ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: lightColor,
      ),
    );
  }
}
