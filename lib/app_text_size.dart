import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTextSize {
  static const String _textSizeKey = "selected_text_size";

  static ValueNotifier<String> currentTextSize = ValueNotifier<String>(
    "normal",
  );

  static const List<String> textSizes = ["normal", "large"];

  static Future<void> loadSavedTextSize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTextSize = prefs.getString(_textSizeKey) ?? "normal";

    if (textSizes.contains(savedTextSize)) {
      currentTextSize.value = savedTextSize;
    } else {
      currentTextSize.value = "normal";
    }
  }

  static Future<void> changeTextSize(String textSize) async {
    if (!textSizes.contains(textSize)) {
      return;
    }

    currentTextSize.value = textSize;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, textSize);
  }

  static double get scaleFactor {
    if (currentTextSize.value == "large") {
      return 1.18;
    }

    return 1.0;
  }

  static String get textSizeName {
    return textSizeNameForTextSize(currentTextSize.value);
  }

  static String textSizeNameForTextSize(String textSize) {
    switch (textSize) {
      case "large":
        return "Large";
      case "normal":
      default:
        return "Normal";
    }
  }
}
