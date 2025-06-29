import 'package:flutter/material.dart';

class AppTheme extends ChangeNotifier {
  static final AppTheme _instance = AppTheme._internal();
  factory AppTheme() => _instance;
  AppTheme._internal();

  static ThemeMode _themeMode = ThemeMode.light;
  static bool get isDarkMode => _themeMode == ThemeMode.dark;

  static void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _instance.notifyListeners();
  }

  static ThemeMode get themeMode => _themeMode;

  // Main color scheme - matching animated login screen
  static const ColorScheme colorScheme = ColorScheme.light(
    primary: Color(0xFF1976D2), // Main blue color
    onPrimary: Colors.white, // Text color on primary elements
    surface: Color(0xFFF5F7FA), // Background color
    onSurface: Color(0xFF2E2E2E), // Main text color
    secondary: Color(0xFF64B5F6), // Accent color
    error: Color(0xFFD32F2F), // Error color
    onError: Colors.white, // Text on error color
  );

  // Common text styles
  static const TextStyle headlineStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Color(0xFF2E2E2E),
  );

  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Color(0xFF2E2E2E),
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 14,
    color: Color(0xFF2E2E2E),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF1976D2),
      onPrimary: Colors.white,
      surface: Color(0xFFF5F7FA),
      onSurface: Color(0xFF2E2E2E),
      secondary: Color(0xFF64B5F6),
      error: Color(0xFFD32F2F),
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1976D2),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Color(0xFF1976D2),
      unselectedLabelColor: Colors.grey,
      indicatorColor: Color(0xFF1976D2),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      selectedIconTheme: IconThemeData(color: Color(0xFF1976D2)),
      selectedLabelTextStyle: TextStyle(color: Color(0xFF1976D2)),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF1976D2),
      onPrimary: Colors.white,
      surface: Color(0xFF121212),
      onSurface: Colors.white,
      secondary: Color(0xFF64B5F6),
      error: Color(0xFFD32F2F),
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A1A),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: Colors.grey.shade900,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Color(0xFF1976D2),
      unselectedLabelColor: Colors.grey,
      indicatorColor: Color(0xFF1976D2),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      selectedIconTheme: IconThemeData(color: Color(0xFF1976D2)),
      selectedLabelTextStyle: TextStyle(color: Color(0xFF1976D2)),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFF1A1A1A),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
  );

  static ThemeData getTheme(bool isDarkMode) {
    return isDarkMode ? darkTheme : lightTheme;
  }

  // Glassmorphic decoration for cards and containers
  static BoxDecoration get glassmorphicDecoration => BoxDecoration(
    color: Colors.white.withOpacity(0.15),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withOpacity(0.18)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );

  // Wave colors for backgrounds
  static List<Color> get waveColors => [
    colorScheme.primary.withOpacity(0.18),
    colorScheme.secondary.withOpacity(0.13),
    colorScheme.primary.withOpacity(0.10),
  ];

  // Status colors
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFFA000);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color infoColor = Color(0xFF1976D2);
}