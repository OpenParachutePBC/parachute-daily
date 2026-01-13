import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import 'package:parachute_daily/core/services/base_server_service.dart';
import 'package:parachute_daily/core/providers/base_server_provider.dart';

/// Server settings section for Parachute Daily
///
/// Configures:
/// - Base server URL (for triggering reflections, viewing curator log, etc.)
class ServerSection extends ConsumerStatefulWidget {
  const ServerSection({super.key});

  @override
  ConsumerState<ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends ConsumerState<ServerSection> {
  final TextEditingController _serverUrlController = TextEditingController();
  bool _isLoading = true;
  bool? _isConnected;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(baseServerServiceProvider);
      final url = await service.getServerUrl();

      setState(() {
        _serverUrlController.text = url;
        _isLoading = false;
      });

      // Check connection in background
      _checkConnection();
    } catch (e) {
      setState(() {
        _serverUrlController.text = 'http://localhost:3333';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkConnection() async {
    final service = ref.read(baseServerServiceProvider);
    final connected = await service.isServerReachable();
    if (mounted) {
      setState(() {
        _isConnected = connected;
      });
    }
  }

  Future<void> _updateServerUrl() async {
    final service = ref.read(baseServerServiceProvider);
    await service.setServerUrl(_serverUrlController.text.trim());

    // Re-check connection with new URL
    setState(() => _isConnected = null);
    await _checkConnection();

    // Invalidate server connectivity provider to update UI elsewhere
    ref.invalidate(serverConnectedProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isConnected == true
              ? 'Connected to server'
              : 'Server URL saved (not connected)'),
          backgroundColor:
              _isConnected == true ? BrandColors.forest : BrandColors.driftwood,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Server',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // Server URL setting
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Base Server URL',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Connection status indicator
                        if (_isConnected != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _isConnected!
                                  ? BrandColors.forest.withOpacity(0.15)
                                  : BrandColors.driftwood.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isConnected!
                                      ? Icons.check_circle
                                      : Icons.cloud_off,
                                  size: 12,
                                  color: _isConnected!
                                      ? BrandColors.forest
                                      : BrandColors.driftwood,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isConnected! ? 'Connected' : 'Not connected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _isConnected!
                                        ? BrandColors.forest
                                        : BrandColors.driftwood,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _serverUrlController,
                            decoration: InputDecoration(
                              hintText: 'http://localhost:3333',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? BrandColors.nightTextSecondary.withOpacity(0.5)
                                    : BrandColors.driftwood.withOpacity(0.5),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? BrandColors.nightSurfaceElevated
                                      : BrandColors.stone,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? BrandColors.nightSurfaceElevated
                                      : BrandColors.stone,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                            ),
                            onSubmitted: (_) => _updateServerUrl(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.refresh,
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                          ),
                          onPressed: () {
                            setState(() => _isConnected = null);
                            _checkConnection();
                          },
                          tooltip: 'Test connection',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Helper text
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'The Parachute Base server URL. Used for generating reflections and viewing curator logs. Leave as localhost if running locally.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? BrandColors.nightTextSecondary.withOpacity(0.7)
                        : BrandColors.driftwood.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}
