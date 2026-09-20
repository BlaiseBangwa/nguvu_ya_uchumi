import 'package:shared_preferences/shared_preferences.dart';

class LicenseService {
  static const String _keyInstallDate = 'install_date';
  static const String _keyIsLicensed = 'is_licensed';

  // Clé de renouvellement par défaut (4 mois supplémentaires ou accès permanent)
  static const String defaultRenewalKey = "ISLAM-2026-UCHUMI";


  static Future<bool> isAppActive() async {
    final prefs = await SharedPreferences.getInstance();

    // Si déjà déverrouillé avec une clé valide
    if (prefs.getBool(_keyIsLicensed) ?? false) {
      return true;
    }

    // Date de première installation
    String? installDateStr = prefs.getString(_keyInstallDate);
    DateTime installDate;

    if (installDateStr == null) {
      installDate = DateTime.now();
      await prefs.setString(_keyInstallDate, installDate.toIso8601String());
    } else {
      installDate = DateTime.parse(installDateStr);
    }


    final daysPassed = DateTime.now().difference(installDate).inDays;
    return daysPassed <= 180;
  }


  static Future<bool> validateKey(String inputKey) async {
    if (inputKey.trim() == defaultRenewalKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLicensed, true);
      return true;
    }
    return false;
  }
}