import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/file_system_service.dart';

/// Result of a photo capture operation.
class CaptureResult {
  /// Absolute path to the saved image file.
  final String absolutePath;

  /// Relative path for storing in journal entries (e.g., "assets/2025-12/...").
  final String relativePath;

  /// Timestamp when the image was captured.
  final DateTime timestamp;

  const CaptureResult({
    required this.absolutePath,
    required this.relativePath,
    required this.timestamp,
  });
}

/// Service for capturing photos from camera or gallery.
///
/// Handles:
/// - Camera capture
/// - Gallery selection
/// - Saving images to the assets folder
class PhotoCaptureService {
  final ImagePicker _picker = ImagePicker();
  final FileSystemService _fileSystem;

  PhotoCaptureService(this._fileSystem);

  /// Capture a photo from the device camera.
  ///
  /// Returns [CaptureResult] with paths to the saved image,
  /// or null if the user cancelled.
  Future<CaptureResult?> captureFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        debugPrint('[PhotoCaptureService] Camera capture cancelled');
        return null;
      }

      return _savePhoto(photo, 'photo');
    } catch (e) {
      debugPrint('[PhotoCaptureService] Error capturing from camera: $e');
      rethrow;
    }
  }

  /// Select a photo from the device gallery.
  ///
  /// Returns [CaptureResult] with paths to the saved image,
  /// or null if the user cancelled.
  Future<CaptureResult?> selectFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo == null) {
        debugPrint('[PhotoCaptureService] Gallery selection cancelled');
        return null;
      }

      return _savePhoto(photo, 'photo');
    } catch (e) {
      debugPrint('[PhotoCaptureService] Error selecting from gallery: $e');
      rethrow;
    }
  }

  /// Save the captured/selected photo to the assets folder.
  Future<CaptureResult> _savePhoto(XFile photo, String type) async {
    final now = DateTime.now();

    // Determine file extension from original file
    final originalExtension = photo.path.split('.').last.toLowerCase();
    final extension = _normalizeExtension(originalExtension);

    // Generate destination path
    final destPath = await _fileSystem.getNewAssetPath(now, type, extension);
    final filename = destPath.split('/').last;
    final relativePath = _fileSystem.getAssetRelativePath(now, filename);

    // Copy the photo to the assets folder
    final sourceFile = File(photo.path);
    await sourceFile.copy(destPath);

    debugPrint('[PhotoCaptureService] Saved photo to: $destPath');
    debugPrint('[PhotoCaptureService] Relative path: $relativePath');

    return CaptureResult(
      absolutePath: destPath,
      relativePath: relativePath,
      timestamp: now,
    );
  }

  /// Save an image from bytes (e.g., from canvas export).
  Future<CaptureResult> saveImageBytes(
    List<int> bytes,
    String type, {
    String extension = 'png',
  }) async {
    final now = DateTime.now();

    // Generate destination path
    final destPath = await _fileSystem.getNewAssetPath(now, type, extension);
    final filename = destPath.split('/').last;
    final relativePath = _fileSystem.getAssetRelativePath(now, filename);

    // Write bytes to file
    final file = File(destPath);
    await file.writeAsBytes(bytes);

    debugPrint('[PhotoCaptureService] Saved image bytes to: $destPath');
    debugPrint('[PhotoCaptureService] Relative path: $relativePath');

    return CaptureResult(
      absolutePath: destPath,
      relativePath: relativePath,
      timestamp: now,
    );
  }

  /// Normalize file extension to common formats.
  String _normalizeExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'jpg';
      case 'png':
        return 'png';
      case 'heic':
      case 'heif':
        // HEIC images from iOS - keep as-is or convert based on needs
        return 'jpg'; // image_picker usually converts to jpg
      default:
        return 'png';
    }
  }
}
