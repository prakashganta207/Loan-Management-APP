// Run once after `flutter create .`:   dart run tool/setup_android.dart
//
// Patches the generated Android project for two things this app needs:
//  1. UPI deep links: Android 11+ hides other apps unless declared in <queries>.
//  2. Fingerprint unlock: local_auth needs FlutterFragmentActivity + USE_BIOMETRIC.
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/ not found. Run `flutter create . --project-name loan_chit_manager` first.');
    exit(1);
  }
  var xml = manifest.readAsStringSync();

  if (!xml.contains('android.permission.USE_BIOMETRIC')) {
    xml = xml.replaceFirstMapped(RegExp(r'<manifest[^>]*>'),
        (m) => '${m[0]}\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>');
  }

  const upiIntent = '''
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="upi"/>
        </intent>''';
  if (!xml.contains('android:scheme="upi"')) {
    if (xml.contains('<queries>')) {
      xml = xml.replaceFirst('<queries>', '<queries>$upiIntent');
    } else {
      xml = xml.replaceFirst('</manifest>', '    <queries>$upiIntent\n    </queries>\n</manifest>');
    }
  }
  manifest.writeAsStringSync(xml);
  stdout.writeln('✓ AndroidManifest.xml: USE_BIOMETRIC + UPI <queries>');

  final activities = Directory('android/app/src/main')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt') || f.path.endsWith('MainActivity.java'));
  for (final f in activities) {
    final src = f.readAsStringSync();
    final patched = src
        .replaceAll('io.flutter.embedding.android.FlutterActivity;',
            'io.flutter.embedding.android.FlutterFragmentActivity;')
        .replaceAll('io.flutter.embedding.android.FlutterActivity\n',
            'io.flutter.embedding.android.FlutterFragmentActivity\n')
        .replaceAll(': FlutterActivity()', ': FlutterFragmentActivity()')
        .replaceAll('extends FlutterActivity', 'extends FlutterFragmentActivity');
    f.writeAsStringSync(patched);
    stdout.writeln('✓ ${f.path}: FlutterFragmentActivity');
  }
  if (activities.isEmpty) stderr.writeln('! MainActivity not found — patch it by hand (see README).');
}
