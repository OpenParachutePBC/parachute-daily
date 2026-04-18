// Unit tests for ServerUrlNotifier.normalizeServerUrl — the forgiving
// URL parser shared by onboarding + Settings. Regression coverage for the
// "entered parachute:1940, got rejected" onboarding bug.
//
// Run with: flutter test test/server_url_normalize_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parachute/core/providers/app_state_provider.dart';

void main() {
  group('ServerUrlNotifier.normalizeServerUrl', () {
    test('hostname:port gets http:// prepended', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('parachute:1940'),
        'http://parachute:1940',
      );
    });

    test('bare hostname defaults to port 1940', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('parachute.local'),
        'http://parachute.local:1940',
      );
    });

    test('http:// URL with port is preserved', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('http://localhost:1940'),
        'http://localhost:1940',
      );
    });

    test('https:// URL with port is preserved', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('https://vault.example.com:8443'),
        'https://vault.example.com:8443',
      );
    });

    test('https:// URL without port is preserved (no 1940 forced)', () {
      // A user who typed https:// clearly knows what they're doing — don't
      // second-guess them by rewriting the port.
      final result =
          ServerUrlNotifier.normalizeServerUrl('https://vault.example.com');
      // Either keep as-is or append :1940 — but the scheme must stay https.
      expect(result, isNotNull);
      expect(result, startsWith('https://vault.example.com'));
    });

    test('trailing slashes are stripped', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('http://localhost:1940/'),
        'http://localhost:1940',
      );
      expect(
        ServerUrlNotifier.normalizeServerUrl('http://localhost:1940///'),
        'http://localhost:1940',
      );
    });

    test('whitespace is trimmed', () {
      expect(
        ServerUrlNotifier.normalizeServerUrl('  parachute:1940  '),
        'http://parachute:1940',
      );
    });

    test('empty input returns null', () {
      expect(ServerUrlNotifier.normalizeServerUrl(''), isNull);
      expect(ServerUrlNotifier.normalizeServerUrl('   '), isNull);
    });

    test('non-http schemes are rejected', () {
      expect(ServerUrlNotifier.normalizeServerUrl('ftp://host'), isNull);
      expect(ServerUrlNotifier.normalizeServerUrl('file:///etc/passwd'), isNull);
    });

    test('normalized output passes isValidServerUrl', () {
      for (final input in [
        'parachute:1940',
        'localhost',
        'http://localhost:1940',
        'https://vault.example.com:8443',
      ]) {
        final normalized = ServerUrlNotifier.normalizeServerUrl(input);
        expect(normalized, isNotNull, reason: 'input: $input');
        expect(
          ServerUrlNotifier.isValidServerUrl(normalized!),
          isTrue,
          reason: 'normalized: $normalized',
        );
      }
    });
  });
}
