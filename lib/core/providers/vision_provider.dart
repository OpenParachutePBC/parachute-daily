import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/vision/vision_service.dart';
import '../services/vision/mobile_vision_service.dart';
import '../services/vision/desktop_vision_service.dart';

/// Provider for mobile vision service (Android/iOS).
///
/// Uses Google ML Kit for text recognition.
final mobileVisionServiceProvider = Provider<VisionService>((ref) {
  final service = MobileVisionService();

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// Provider for desktop vision service (macOS/Linux/Windows).
///
/// Currently a placeholder - desktop OCR not yet implemented.
final desktopVisionServiceProvider = Provider<VisionService>((ref) {
  final service = DesktopVisionService();

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// Provider for the vision service.
///
/// Automatically selects the appropriate implementation based on platform:
/// - Mobile (Android/iOS): Google ML Kit
/// - Desktop (macOS/Linux/Windows): Not yet implemented
final visionServiceProvider = Provider<VisionService>((ref) {
  if (Platform.isAndroid || Platform.isIOS) {
    return ref.watch(mobileVisionServiceProvider);
  } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    return ref.watch(desktopVisionServiceProvider);
  } else {
    throw UnimplementedError(
      'Vision service not available on this platform: ${Platform.operatingSystem}',
    );
  }
});

/// Status of the vision service
enum VisionServiceStatus {
  /// Vision service is ready to use
  ready,

  /// Vision service is not available (e.g., desktop without OCR)
  notAvailable,

  /// Error occurred while checking status
  error,
}

/// State for vision service status
class VisionStatusState {
  final VisionServiceStatus status;
  final bool isReady;
  final bool isProcessing;
  final String? error;

  const VisionStatusState({
    this.status = VisionServiceStatus.notAvailable,
    this.isReady = false,
    this.isProcessing = false,
    this.error,
  });

  VisionStatusState copyWith({
    VisionServiceStatus? status,
    bool? isReady,
    bool? isProcessing,
    String? error,
  }) {
    return VisionStatusState(
      status: status ?? this.status,
      isReady: isReady ?? this.isReady,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
    );
  }
}

/// Notifier that tracks vision service status
class VisionStatusNotifier extends StateNotifier<VisionStatusState> {
  final Ref _ref;

  VisionStatusNotifier(this._ref) : super(const VisionStatusState()) {
    // Check status on creation
    checkStatus();
  }

  /// Check current vision service status
  Future<void> checkStatus() async {
    try {
      final service = _ref.read(visionServiceProvider);
      final isReady = await service.isReady();

      if (isReady) {
        state = state.copyWith(
          status: VisionServiceStatus.ready,
          isReady: true,
        );
      } else {
        state = state.copyWith(
          status: VisionServiceStatus.notAvailable,
          isReady: false,
        );
      }
      debugPrint('[VisionStatus] Status check: isReady=$isReady');
    } catch (e) {
      debugPrint('[VisionStatus] Error checking status: $e');
      state = state.copyWith(
        status: VisionServiceStatus.error,
        error: e.toString(),
        isReady: false,
      );
    }
  }

  /// Set processing state
  void setProcessing(bool processing) {
    state = state.copyWith(isProcessing: processing);
  }
}

/// Provider for vision service status with proper state management
final visionStatusProvider =
    StateNotifierProvider<VisionStatusNotifier, VisionStatusState>((ref) {
  return VisionStatusNotifier(ref);
});

/// Provider to check if vision (OCR) is available on this platform
final visionAvailableProvider = Provider<bool>((ref) {
  // ML Kit is available on mobile only
  return Platform.isAndroid || Platform.isIOS;
});
