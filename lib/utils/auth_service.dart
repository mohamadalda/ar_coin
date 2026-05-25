import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);
  
  // Base64 encoded credentials to avoid plaintext hardcoding
  // admin_imago
  static const String _encodedUsername = 'YWRtaW5faW1hZ28=';
  // imG0menang
  static const String _encodedPassword = 'aW1HMG1lbmFuZw==';

  static const String _loginPrefKey = 'is_admin_logged_in';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isLoggedIn.value = prefs.getBool(_loginPrefKey) ?? false;
  }

  static Future<bool> login(String username, String password) async {
    final decodedUsername = utf8.decode(base64Decode(_encodedUsername));
    final decodedPassword = utf8.decode(base64Decode(_encodedPassword));

    if (username == decodedUsername && password == decodedPassword) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loginPrefKey, true);
      isLoggedIn.value = true;
      return true;
    }
    return false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginPrefKey, false);
    isLoggedIn.value = false;
  }
}
