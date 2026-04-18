import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

// computer_service.dart removed in v2 — no longer needed

/// App flavor set at compile time via --dart-define=FLAVOR=daily|client|computer
/// Defaults to 'client' if not specified
///
/// Flavors:
/// - daily: Offline journal only, no server features
/// - client: Standard app - connects to external server (default)
/// - computer: Desktop Parachute Computer (server + Docker sandboxing)
const String appFlavor = String.fromEnvironment('FLAVOR', defaultValue: 'client');

/// Whether the app was built as the Daily-only flavor
bool get isDailyOnlyFlavor => appFlavor == 'daily';

/// Whether the app was built as the Client flavor (external server)
bool get isClientFlavor => appFlavor == 'client';

/// Whether the app was built as the Computer flavor
bool get isComputerFlavor => appFlavor == 'computer';

// ============================================================================
// Server URL
// ============================================================================

/// Notifier for server URL with persistence
class ServerUrlNotifier extends AsyncNotifier<String?> {
  static const _key = 'parachute_server_url';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Validate that a URL is well-formed and uses http/https
  static bool isValidServerUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
             (uri.scheme == 'http' || uri.scheme == 'https') &&
             uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Canonicalize a user-entered server URL.
  ///
  /// Forgiving normalization for onboarding / settings:
  /// - Trims whitespace and strips trailing slashes.
  /// - Prepends `http://` when no scheme is given (Parachute Vaults run over
  ///   plain http on the local network by default; users who want TLS can
  ///   type `https://` themselves).
  /// - Defaults to port 1940 (Parachute Vault's default) when no port is given.
  ///
  /// Returns null when the input can't be salvaged into a valid http/https URL.
  static String? normalizeServerUrl(String input) {
    var u = input.trim();
    if (u.isEmpty) return null;
    u = u.replaceAll(RegExp(r'/+$'), '');

    // Distinguish "explicit scheme" from "bare host" — `foo://bar` means the
    // user wrote a scheme, `foo:1940` means hostname:port. If they wrote a
    // scheme, it has to be http or https; otherwise reject.
    if (u.contains('://')) {
      if (!u.startsWith('http://') && !u.startsWith('https://')) {
        return null;
      }
    } else {
      u = 'http://$u';
    }

    Uri uri;
    try {
      uri = Uri.parse(u);
    } catch (_) {
      return null;
    }
    if (!uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (!uri.hasPort) {
      uri = uri.replace(port: 1940);
    }
    final normalized = uri.toString().replaceAll(RegExp(r'/+$'), '');
    return isValidServerUrl(normalized) ? normalized : null;
  }

  Future<void> setServerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      // Validate URL before saving
      if (!isValidServerUrl(url)) {
        throw ArgumentError('Invalid server URL: must be a valid http:// or https:// URL');
      }
      await prefs.setString(_key, url);
      state = AsyncData(url);
    } else {
      await prefs.remove(_key);
      state = const AsyncData(null);
    }
  }
}

/// Server URL provider with notifier for updates
final serverUrlProvider = AsyncNotifierProvider<ServerUrlNotifier, String?>(() {
  return ServerUrlNotifier();
});

/// Notifier for selected vault name with persistence.
///
/// When set, API calls route to `/vaults/{name}/api/*` instead of `/api/*`.
/// Empty or null means use the default vault.
class VaultNameNotifier extends AsyncNotifier<String?> {
  static const _key = 'parachute_vault_name';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> setVaultName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null && name.isNotEmpty) {
      await prefs.setString(_key, name);
      state = AsyncData(name);
    } else {
      await prefs.remove(_key);
      state = const AsyncData(null);
    }
  }
}

/// Selected vault name provider (null = default vault)
final vaultNameProvider = AsyncNotifierProvider<VaultNameNotifier, String?>(() {
  return VaultNameNotifier();
});

/// Notifier for API key with persistence via flutter_secure_storage.
///
/// Uses platform-specific encrypted storage (Keychain on iOS/macOS,
/// EncryptedSharedPreferences on Android, libsecret on Linux).
/// Automatically migrates keys from the old SharedPreferences storage.
class ApiKeyNotifier extends AsyncNotifier<String?> {
  static const _key = 'parachute_api_key';
  static const _secureStorage = FlutterSecureStorage();

  @override
  Future<String?> build() async {
    // Try secure storage first
    final secureKey = await _secureStorage.read(key: _key);
    if (secureKey != null) return secureKey;

    // Migrate from SharedPreferences if present
    final prefs = await SharedPreferences.getInstance();
    final legacyStored = prefs.getString(_key);
    if (legacyStored != null) {
      String plainKey;
      try {
        plainKey = String.fromCharCodes(base64Decode(legacyStored));
      } catch (_) {
        // Unencoded legacy value
        plainKey = legacyStored;
      }
      // Migrate to secure storage and remove from SharedPreferences
      await _secureStorage.write(key: _key, value: plainKey);
      await prefs.remove(_key);
      debugPrint('[ApiKey] Migrated from SharedPreferences to secure storage');
      return plainKey;
    }

    return null;
  }

  Future<void> setApiKey(String? key) async {
    if (key != null && key.isNotEmpty) {
      await _secureStorage.write(key: _key, value: key);
      state = AsyncData(key);
    } else {
      await _secureStorage.delete(key: _key);
      state = const AsyncData(null);
    }
  }
}

/// API key provider with notifier for updates
final apiKeyProvider = AsyncNotifierProvider<ApiKeyNotifier, String?>(() {
  return ApiKeyNotifier();
});

/// Notifier for onboarding completion state
class OnboardingNotifier extends AsyncNotifier<bool> {
  static const _key = 'parachute_onboarding_complete';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = const AsyncData(true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = const AsyncData(false);
  }
}

/// Provider for onboarding completion state
final onboardingCompleteProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(() {
  return OnboardingNotifier();
});

// ============================================================================
// App Version
// ============================================================================

/// App version info from pubspec.yaml (loaded at runtime via package_info_plus)
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Full app version with build number (e.g., "0.2.3+1")
final appVersionFullProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

// ============================================================================
// Setup Reset (for testing/troubleshooting)
// ============================================================================

/// Reset all setup-related state to start fresh.
///
/// Clears server URL, vault name, and onboarding flag.
/// Does NOT clear API key (user might want to keep it).
Future<void> resetSetup(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.remove('parachute_server_url');
  await prefs.remove('parachute_vault_name');
  await prefs.remove('parachute_onboarding_complete');

  ref.invalidate(serverUrlProvider);
  ref.invalidate(vaultNameProvider);
  ref.invalidate(onboardingCompleteProvider);
}
