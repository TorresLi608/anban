import 'package:anban/services/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows HTTPS, local HTTP and the designated HTTP test server', () {
    for (final base in [
      'https://api.example.com',
      'http://localhost:8024',
      'http://127.0.0.1:8024',
      'http://10.0.2.2:8024',
      'http://[::1]:8024',
      'http://103.236.97.108:8024',
    ]) {
      expect(
        VaultSync(base, '').url,
        Uri.parse('$base/api/v1/vault'),
        reason: base,
      );
    }
  });

  test('HTTP exception preserves host and URL validation', () {
    for (final base in [
      'http://103.236.97.109:8024',
      'http://api.example.com',
      'http://103.236.97.108.example.com:8024',
      'http://103.236.97.108@evil.example:8024',
      'http://user:password@103.236.97.108:8024',
      'http://103.236.97.108:8024?token=secret',
      'http://103.236.97.108:8024#fragment',
      'ftp://103.236.97.108:8024',
      'http:///missing-host',
    ]) {
      expect(() => VaultSync(base, ''), throwsFormatException, reason: base);
    }
  });
}
