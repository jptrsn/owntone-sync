package dev.educoder.owntone_sync

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val EVENTS_CHANNEL = "dev.educoder.owntone_sync/events"
    private val STORAGE_CHANNEL = "dev.educoder.owntone_sync/storage"
    private val REQUEST_CODE_MUSIC_FOLDER = 1001

    private var pendingMusicFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Events channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    startActivity(intent)
                    result.success(null)
                }
                "isNotificationPermissionGranted" -> {
                    val enabled = isNotificationServiceEnabled()
                    result.success(enabled)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Storage channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasMusicFolderAccess" -> {
                    result.success(hasMusicFolderAccess())
                }
                "requestMusicFolderAccess" -> {
                    requestMusicFolderAccess(result)
                }
                "getMusicFolderUri" -> {
                    result.success(getMusicFolderUri())
                }
                "fileExists" -> {
                    fileExists(call, result)
                }
                "getFileSize" -> {
                    getFileSize(call, result)
                }
                "deleteFile" -> {
                    deleteFile(call, result)
                }
                "writeFile" -> {
                    writeFile(call, result)
                }
                "writeFileString" -> {
                    writeFileString(call, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        return enabledListeners?.contains(packageName) == true
    }

    private fun hasMusicFolderAccess(): Boolean {
        val uriString = getSharedPreferences("storage_prefs", MODE_PRIVATE)
            .getString("music_folder_uri", null) ?: return false

        val uri = Uri.parse(uriString)

        // Check if we still have permission
        val persistedUris = contentResolver.persistedUriPermissions
        return persistedUris.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
    }

    private fun getMusicFolderUri(): String? {
        return getSharedPreferences("storage_prefs", MODE_PRIVATE)
            .getString("music_folder_uri", null)
    }

    private fun requestMusicFolderAccess(result: MethodChannel.Result) {
        pendingMusicFolderResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

            // Pre-suggest the Music folder
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val musicUri = DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents",
                    "primary:Music"
                )
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, musicUri)
            }
        }

        startActivityForResult(intent, REQUEST_CODE_MUSIC_FOLDER)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE_MUSIC_FOLDER) {
            val result = pendingMusicFolderResult
            pendingMusicFolderResult = null

            if (resultCode == RESULT_OK && data != null) {
                val uri = data.data
                if (uri != null) {
                    // Take persistable permission
                    val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    // Save to SharedPreferences
                    getSharedPreferences("storage_prefs", MODE_PRIVATE)
                        .edit()
                        .putString("music_folder_uri", uri.toString())
                        .apply()

                    result?.success(true)
                } else {
                    result?.success(false)
                }
            } else {
                result?.success(false)
            }
        }
    }

    private fun getMusicFolderDocumentFile(): DocumentFile? {
        val uriString = getMusicFolderUri() ?: return null
        val uri = Uri.parse(uriString)
        return DocumentFile.fromTreeUri(this, uri)
    }

    private fun getDocumentFileFromPath(filePath: String): DocumentFile? {
        val musicFolder = getMusicFolderDocumentFile() ?: return null

        // Extract relative path from absolute path
        // e.g., "/storage/emulated/0/Music/tracks/song.mp3" -> "tracks/song.mp3"
        val relativePath = filePath.substringAfter("/Music/")

        // Navigate through folder structure
        val pathParts = relativePath.split("/")
        var currentFolder = musicFolder

        // Navigate to parent folders
        for (i in 0 until pathParts.size - 1) {
            val folderName = pathParts[i]
            var folder = currentFolder.findFile(folderName)

            if (folder == null || !folder.isDirectory) {
                // Create folder if it doesn't exist
                folder = currentFolder.createDirectory(folderName) ?: return null
            }

            currentFolder = folder
        }

        // Return or create the file
        val fileName = pathParts.last()
        return currentFolder.findFile(fileName)
    }

    private fun createDocumentFileFromPath(filePath: String, mimeType: String): DocumentFile? {
        val musicFolder = getMusicFolderDocumentFile() ?: return null

        val relativePath = filePath.substringAfter("/Music/")
        val pathParts = relativePath.split("/")
        var currentFolder = musicFolder

        // Navigate/create parent folders
        for (i in 0 until pathParts.size - 1) {
            val folderName = pathParts[i]
            var folder = currentFolder.findFile(folderName)

            if (folder == null || !folder.isDirectory) {
                folder = currentFolder.createDirectory(folderName) ?: return null
            }

            currentFolder = folder
        }

        // Create the file
        val fileName = pathParts.last()

        // Delete existing file if present
        currentFolder.findFile(fileName)?.delete()

        return currentFolder.createFile(mimeType, fileName)
    }

    private fun fileExists(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            result.error("INVALID_ARGUMENT", "File path is required", null)
            return
        }

        val file = getDocumentFileFromPath(filePath)
        result.success(file?.exists() == true)
    }

    private fun getFileSize(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            result.error("INVALID_ARGUMENT", "File path is required", null)
            return
        }

        val file = getDocumentFileFromPath(filePath)
        if (file?.exists() == true) {
            result.success(file.length())
        } else {
            result.success(0)
        }
    }

    private fun deleteFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            result.error("INVALID_ARGUMENT", "File path is required", null)
            return
        }

        try {
            val file = getDocumentFileFromPath(filePath)
            val deleted = file?.delete() ?: false
            result.success(deleted)
        } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message, null)
        }
    }

    private fun writeFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        val data = call.argument<ByteArray>("data")

        if (filePath == null || data == null) {
            result.error("INVALID_ARGUMENT", "File path and data are required", null)
            return
        }

        try {
            // Determine MIME type from extension
            val extension = filePath.substringAfterLast('.', "")
            val mimeType = when (extension) {
                "mp3" -> "audio/mpeg"
                "flac" -> "audio/flac"
                "m4a" -> "audio/mp4"
                "wav" -> "audio/wav"
                "aac" -> "audio/aac"
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                else -> "application/octet-stream"
            }

            val file = createDocumentFileFromPath(filePath, mimeType)
            if (file == null) {
                result.error("CREATE_FAILED", "Could not create file", null)
                return
            }

            contentResolver.openOutputStream(file.uri)?.use { output ->
                output.write(data)
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message, null)
        }
    }

    private fun writeFileString(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        val content = call.argument<String>("content")

        if (filePath == null || content == null) {
            result.error("INVALID_ARGUMENT", "File path and content are required", null)
            return
        }

        try {
            val mimeType = "text/plain"
            val file = createDocumentFileFromPath(filePath, mimeType)

            if (file == null) {
                result.error("CREATE_FAILED", "Could not create file", null)
                return
            }

            contentResolver.openOutputStream(file.uri)?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message, null)
        }
    }
}