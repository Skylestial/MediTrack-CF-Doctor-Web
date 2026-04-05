import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  void _loadTheme() {
    if (kIsWeb) {
      final saved = html.window.localStorage['meditrack_theme'];
      if (saved == 'dark') {
        _themeMode = ThemeMode.dark;
        notifyListeners();
      }
    }
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    if (kIsWeb) {
      html.window.localStorage['meditrack_theme'] = isDarkMode ? 'dark' : 'light';
    }
    notifyListeners();
  }
}
