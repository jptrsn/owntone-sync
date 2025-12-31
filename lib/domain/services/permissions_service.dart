import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Check if we have the necessary storage permissions
  Future<bool> hasStoragePermission() async {
    // Check for manage external storage (Android 11+)
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // On Android 13+ (API 33+), we need READ_MEDIA_AUDIO
    if (await Permission.audio.isGranted) {
      return true;
    }

    if (await Permission.storage.isGranted) {
      return true;
    }

    return false;
  }

  /// Request storage permissions
  Future<bool> requestStoragePermission() async {
    // Try to request manage external storage first (Android 11+)
    PermissionStatus status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return true;
    }

    // Try audio permission (Android 13+)
    status = await Permission.audio.request();
    if (status.isGranted) {
      return true;
    }

    // Fall back to storage permission (older Android)
    status = await Permission.storage.request();
    if (status.isGranted) {
      return true;
    }

    return false;
  }

  /// Check if permission was permanently denied
  Future<bool> isStoragePermissionPermanentlyDenied() async {
    return await Permission.manageExternalStorage.isPermanentlyDenied ||
        await Permission.audio.isPermanentlyDenied ||
        await Permission.storage.isPermanentlyDenied;
  }

  /// Check if we have notification listener permission (for playback tracking)
  Future<bool> hasNotificationPermission() async {
    return await Permission.notification.isGranted;
  }

  /// Request notification listener permission
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Open app settings (for when permissions are permanently denied)
  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
