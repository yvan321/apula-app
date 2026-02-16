import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  
  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Initialize the theme provider and load saved preference
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedTheme = _prefs.getString(_themeKey) ?? 'dark';
    
    switch (savedTheme) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'system':
        _themeMode = ThemeMode.system;
        break;
      default:
        _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  /// Toggle between light and dark mode
  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    await _prefs.setString(_themeKey, isDark ? 'dark' : 'light');
    notifyListeners();
  }

  /// Set theme to system preference
  Future<void> setSystemTheme() async {
    _themeMode = ThemeMode.system;
    await _prefs.setString(_themeKey, 'system');
    notifyListeners();
  }
}
