import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/providers/app_state_provider.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/settings/services/oauth_service.dart';

export 'package:parachute/core/providers/app_state_provider.dart' show isDailyOnlyFlavor;

/// Steps in the onboarding flow.
enum _Step { welcome, connect, done }

/// First-run setup. Mirrors [ServerSettingsSection] so the OAuth-first
/// connect flow is available before the user ever reaches Settings.
///
/// Welcome → Connect → Done.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;

  final _serverUrlController = TextEditingController(text: AppConfig.defaultServerUrl);
  final _vaultNameController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _connecting = false;
  bool _showManualToken = false;
  String? _errorMessage;

  /// Vault we ended up connected to (server-reported or user-typed), shown
  /// on the success screen.
  String? _connectedVault;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _vaultNameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  // ---- Step transitions ----

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _errorMessage = null;
    });
  }

  /// Read the URL field, normalize it, write the normalized value back to
  /// the field so the user sees what we actually use. Returns null if the
  /// input can't be salvaged.
  String? _readAndNormalizeUrl() {
    final normalized = ServerUrlNotifier.normalizeServerUrl(_serverUrlController.text);
    if (normalized == null) {
      setState(() {
        _errorMessage = "That doesn't look like a valid server. "
            'Try something like `parachute:1940` or `https://vault.example.com`.';
      });
      return null;
    }
    if (_serverUrlController.text != normalized) {
      _serverUrlController.text = normalized;
    }
    return normalized;
  }

  Future<void> _connectOAuth() async {
    setState(() {
      _errorMessage = null;
      _connecting = true;
    });

    final url = _readAndNormalizeUrl();
    if (url == null) {
      setState(() => _connecting = false);
      return;
    }
    final requestedVault = _vaultNameController.text.trim();

    // Persist URL + any requested vault name before launching the browser,
    // so dependent providers see them and so a mid-flow quit still leaves
    // the app in a reasonable state.
    try {
      await ref.read(serverUrlProvider.notifier).setServerUrl(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = 'Invalid server URL: $e';
      });
      return;
    }
    if (requestedVault.isNotEmpty) {
      await ref.read(vaultNameProvider.notifier).setVaultName(requestedVault);
    }

    final oauth = OAuthService();
    try {
      final result = await oauth.connect(
        serverUrl: url,
        vaultName: requestedVault.isEmpty ? null : requestedVault,
      );
      await ref.read(apiKeyProvider.notifier).setApiKey(result.token);
      // Prefer server-reported vault so later routing matches the token.
      final finalVault = result.vaultName ?? (requestedVault.isEmpty ? null : requestedVault);
      await ref.read(vaultNameProvider.notifier).setVaultName(finalVault);

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectedVault = finalVault;
      });
      _goTo(_Step.done);
    } on OAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = 'Connection failed: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = 'Connection failed: $e';
      });
    } finally {
      oauth.dispose();
    }
  }

  Future<void> _saveManualToken() async {
    setState(() {
      _errorMessage = null;
      _connecting = true;
    });

    final url = _readAndNormalizeUrl();
    if (url == null) {
      setState(() => _connecting = false);
      return;
    }
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _connecting = false;
        _errorMessage = 'Paste a bearer token, or use Connect to Vault.';
      });
      return;
    }

    try {
      await ref.read(serverUrlProvider.notifier).setServerUrl(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = 'Invalid server URL: $e';
      });
      return;
    }
    final vaultName = _vaultNameController.text.trim();
    await ref
        .read(vaultNameProvider.notifier)
        .setVaultName(vaultName.isEmpty ? null : vaultName);
    await ref.read(apiKeyProvider.notifier).setApiKey(key);

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connectedVault = vaultName.isEmpty ? null : vaultName;
    });
    _goTo(_Step.done);
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingCompleteProvider.notifier).markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  /// Finish onboarding without connecting — offline mode. User can complete
  /// setup later in Settings.
  Future<void> _continueOffline() async {
    await _completeOnboarding();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? BrandColors.nightSurface : BrandColors.cream;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: switch (_step) {
            _Step.welcome => _buildWelcome(isDark),
            _Step.connect => _buildConnect(isDark),
            _Step.done => _buildDone(isDark),
          },
        ),
      ),
    );
  }

  // ---- Step views ----

  Widget _buildWelcome(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Icon(
          Icons.today,
          size: 80,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        SizedBox(height: Spacing.xl),
        _title('Parachute Daily', isDark),
        SizedBox(height: Spacing.md),
        _subtitle('Your personal graph.\nJournal in, AI plugs in.', isDark),
        const Spacer(),
        _primaryButton('Get Started', isDark, () => _goTo(_Step.connect)),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildConnect(bool isDark) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - Spacing.xl * 2,
        ),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: Spacing.xl),
              _stepHeader('Connect to your vault', isDark),
              SizedBox(height: Spacing.md),
              _subtitle(
                "Parachute Daily syncs with a Parachute Vault. Enter your vault's "
                "URL — we'll open your browser to authorize.",
                isDark,
              ),
              SizedBox(height: Spacing.xl),

              // Server URL
              TextField(
                controller: _serverUrlController,
                enabled: !_connecting,
                autocorrect: false,
                keyboardType: TextInputType.url,
                style: TextStyle(
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'parachute:1940 or https://vault.example.com',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.softWhite,
                ),
              ),
              SizedBox(height: Spacing.md),

              // Vault name (optional)
              TextField(
                controller: _vaultNameController,
                enabled: !_connecting,
                autocorrect: false,
                style: TextStyle(
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
                decoration: InputDecoration(
                  labelText: 'Vault name (optional)',
                  hintText: 'Leave blank for default',
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.softWhite,
                ),
              ),

              if (_errorMessage != null) ...[
                SizedBox(height: Spacing.md),
                _errorText(_errorMessage!),
              ],

              SizedBox(height: Spacing.lg),

              // Primary: Connect to Vault (OAuth)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _connecting ? null : _connectOAuth,
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open, size: 18),
                  label: Text(_connecting ? 'Connecting…' : 'Connect to Vault'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? BrandColors.nightForest : BrandColors.forest,
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                ),
              ),

              SizedBox(height: Spacing.sm),

              // Advanced: paste a bearer token
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _connecting
                      ? null
                      : () => setState(() {
                            _showManualToken = !_showManualToken;
                            _errorMessage = null;
                          }),
                  child: Text(
                    _showManualToken
                        ? 'Hide advanced'
                        : 'Advanced: paste a bearer token',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),

              if (_showManualToken) ...[
                SizedBox(height: Spacing.xs),
                TextField(
                  controller: _apiKeyController,
                  enabled: !_connecting,
                  obscureText: true,
                  autocorrect: false,
                  style: TextStyle(
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'pvt_… or para_…',
                    prefixIcon: const Icon(Icons.key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? BrandColors.nightSurfaceElevated
                        : BrandColors.softWhite,
                  ),
                ),
                SizedBox(height: Spacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _connecting ? null : _saveManualToken,
                    child: const Text('Save token and continue'),
                  ),
                ),
              ],

              const Spacer(),

              _secondaryButton(
                'Back',
                isDark,
                _connecting ? null : () => _goTo(_Step.welcome),
              ),
              TextButton(
                onPressed: _connecting ? null : _continueOffline,
                child: Text(
                  'Skip — use offline',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ),
              SizedBox(height: Spacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDone(bool isDark) {
    final vault = _connectedVault;
    final subtitle = vault == null || vault.isEmpty
        ? 'Connected. Time to capture something.'
        : 'Connected to vault "$vault". Time to capture something.';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Icon(
          Icons.check_circle,
          size: 80,
          color: BrandColors.success,
        ),
        SizedBox(height: Spacing.xl),
        _title("You're ready", isDark),
        SizedBox(height: Spacing.md),
        _subtitle(subtitle, isDark),
        const Spacer(),
        _primaryButton('Start Capturing', isDark, _completeOnboarding),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  // ---- Shared widgets ----

  Widget _title(String text, bool isDark) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: TypographyTokens.headlineLarge,
          fontWeight: FontWeight.bold,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
      );

  Widget _stepHeader(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: TypographyTokens.headlineMedium,
          fontWeight: FontWeight.bold,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
      );

  Widget _subtitle(String text, bool isDark) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: TypographyTokens.bodyLarge,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          height: 1.4,
        ),
      );

  Widget _errorText(String text) => Text(
        text,
        style: TextStyle(
          color: BrandColors.error,
          fontSize: TypographyTokens.bodyMedium,
        ),
      );

  Widget _primaryButton(String label, bool isDark, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
          padding: EdgeInsets.symmetric(vertical: Spacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _secondaryButton(String label, bool isDark, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      ),
    );
  }
}
