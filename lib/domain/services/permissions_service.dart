import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter/services.dart';

class PermissionsService {
  static const _storageChannel = MethodChannel(
    'dev.educoder.owntone_sync/storage',
  );

  bool _isRequestingPermission = false;

  /// Check if we have the necessary storage permissions
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Check for READ_MEDIA_AUDIO (Android 13+) or fallback permission
    final hasAudioPermission =
        await ph.Permission.audio.isGranted ||
        await ph.Permission.storage.isGranted;

    // Check for SAF folder access
    final hasFolderAccess = await _hasFolderAccess();

    return hasAudioPermission && hasFolderAccess;
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Request appropriate audio/storage permission
    var audioStatus = await ph.Permission.audio.status;
    if (!audioStatus.isGranted) {
      audioStatus = await ph.Permission.audio.request();

      // Fallback to storage permission on older devices
      if (!audioStatus.isGranted) {
        final storageStatus = await ph.Permission.storage.request();
        if (!storageStatus.isGranted) {
          return false;
        }
      }
    }

    // Request SAF folder access on ALL Android versions
    final result = await _requestFolderAccess();
    return result;
  }

  /// Check if permission was permanently denied
  Future<bool> isStoragePermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    return await ph.Permission.audio.isPermanentlyDenied ||
        await ph.Permission.storage.isPermanentlyDenied;
  }

  /// Check if we have folder access via SAF
  Future<bool> _hasFolderAccess() async {
    try {
      final result = await _storageChannel.invokeMethod<bool>(
        'hasMusicFolderAccess',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Request folder access via SAF
  Future<bool> _requestFolderAccess() async {
    try {
      final result = await _storageChannel.invokeMethod<bool>(
        'requestMusicFolderAccess',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Open app settings (for when permissions are permanently denied)
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  // Check if allowed to show notifications
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    return await ph.Permission.notification.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    
    // Prevent concurrent permission requests
    if (_isRequestingPermission) {
      return false;
    }
    
    _isRequestingPermission = true;
    try {
      final status = await ph.Permission.notification.request();
      return status.isGranted;
    } finally {
      _isRequestingPermission = false;
    }
  }
}
