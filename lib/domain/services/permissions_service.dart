import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter/services.dart';

class PermissionsService {
  static const _storageChannel = MethodChannel(
    'dev.educoder.owntone_sync/storage',
  );

  /// Get Android SDK version
  Future<int> _getAndroidSdk() async {
    if (!Platform.isAndroid) return 0;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt;
  }

  /// Check if we have the necessary storage permissions
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdk = await _getAndroidSdk();

    if (sdk >= 33) {
      // Android 13+: Need READ_MEDIA_AUDIO + SAF Music folder access
      final hasAudioPermission = await ph.Permission.audio.isGranted;
      final hasFolderAccess = await _hasMusicFolderAccess();
      return hasAudioPermission && hasFolderAccess;
    } else {
      // Android 10-12: Need WRITE_EXTERNAL_STORAGE
      return await ph.Permission.storage.isGranted;
    }
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdk = await _getAndroidSdk();
    print('DEBUG: Requesting permission for SDK $sdk'); // DEBUG

    if (sdk >= 33) {
      print('DEBUG: Requesting READ_MEDIA_AUDIO...'); // DEBUG
      final audioStatus = await ph.Permission.audio.request();
      print(
        'DEBUG: Audio permission result: ${audioStatus.isGranted}',
      ); // DEBUG

      if (!audioStatus.isGranted) {
        return false;
      }

      print('DEBUG: Requesting Music folder access...'); // DEBUG
      final result = await _requestMusicFolderAccess();
      print('DEBUG: SAF picker result: $result'); // DEBUG
      return result;
    } else {
      // Android 10-12: Request WRITE_EXTERNAL_STORAGE explicitly
      print('DEBUG: Requesting WRITE_EXTERNAL_STORAGE...'); // DEBUG
      final status = await ph.Permission.storage.request();
      print('DEBUG: Storage permission granted: ${status.isGranted}'); // DEBUG
      print('DEBUG: Storage permission status: ${status}'); // DEBUG
      return status.isGranted;
    }
  }

  /// Check if permission was permanently denied
  Future<bool> isStoragePermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    final sdk = await _getAndroidSdk();

    if (sdk >= 33) {
      return await ph.Permission.audio.isPermanentlyDenied;
    } else {
      return await ph.Permission.storage.isPermanentlyDenied;
    }
  }

  /// Check if we have Music folder access (Android 13+ only)
  Future<bool> _hasMusicFolderAccess() async {
    try {
      final result = await _storageChannel.invokeMethod<bool>(
        'hasMusicFolderAccess',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Request Music folder access via SAF (Android 13+ only)
  Future<bool> _requestMusicFolderAccess() async {
    try {
      final result = await _storageChannel.invokeMethod<bool>(
        'requestMusicFolderAccess',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get the persisted Music folder URI (for use in FileSystemRepository)
  Future<String?> getMusicFolderUri() async {
    if (!Platform.isAndroid) return null;

    final sdk = await _getAndroidSdk();
    if (sdk < 33) return null;

    try {
      final uri = await _storageChannel.invokeMethod<String>(
        'getMusicFolderUri',
      );
      return uri;
    } catch (e) {
      return null;
    }
  }

  /// Open app settings (for when permissions are permanently denied)
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }
}
