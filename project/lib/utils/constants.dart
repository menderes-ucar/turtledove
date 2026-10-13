class AppConstants {
  static const appName = 'Bestie';
  static const appVersion = '1.0.0';
}

class AppValidators {
  static bool isValidEmail(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  static bool isValidPassword(String password) {
    return password.length >= 6;
  }

  static bool isValidUsername(String username) {
    return username.length >= 3 && username.length <= 20;
  }
}
