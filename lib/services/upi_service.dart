import 'package:url_launcher/url_launcher.dart';

import 'settings_service.dart';

class UpiConfig {
  const UpiConfig(this.upiId, this.payeeName);
  final String upiId;
  final String payeeName;
}

class UpiService {
  UpiService([SettingsService? settings]) : _settings = settings ?? SettingsService();
  final SettingsService _settings;

  Future<UpiConfig?> config() async {
    final id = await _settings.get(SettingsKeys.upiId);
    if (id == null || id.trim().isEmpty) return null;
    final name = await _settings.get(SettingsKeys.upiPayeeName);
    return UpiConfig(id.trim(), (name == null || name.trim().isEmpty) ? 'Lender' : name.trim());
  }

  /// upi://pay?pa=..&pn=..&am=..&cu=INR&tn=..  (spaces encoded as %20, which
  /// UPI apps handle more reliably than '+').
  static Uri buildUri({
    required String upiId,
    required String payeeName,
    required double amount,
    required String note,
  }) {
    String e(String s) => Uri.encodeComponent(s);
    return Uri.parse('upi://pay?pa=${e(upiId)}&pn=${e(payeeName)}'
        '&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${e(note)}');
  }

  Future<bool> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
