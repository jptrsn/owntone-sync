package dev.educoder.owntone_sync

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.OutputStream

class FileOperations(private val context: Context) {

    fun getMusicFolderUri(): String? {
        return context.getSharedPreferences("storage_prefs", Context.MODE_PRIVATE)
            .getString("music_folder_uri", null)
    }

    private fun getMusicFolderDocumentFile(): DocumentFile? {
        val uriString = getMusicFolderUri() ?: return null
        val uri = Uri.parse(uriString)
        return DocumentFile.fromTreeUri(context, uri)
    }

    fun fileExists(filePath: String): Boolean {
        val file = getDocumentFileFromPath(filePath)
        return file?.exists() == true
    }

    fun writeFile(filePath: String, data: ByteArray): Boolean {
        try {
            val musicFolder = getMusicFolderDocumentFile() ?: return false

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
                "m3u" -> "audio/x-mpegurl"
                else -> "application/octet-stream"
            }

            // Path is already relative
            val pathParts = filePath.split("/")
            var currentFolder: DocumentFile = musicFolder

            // Navigate/create parent folders
            for (i in 0 until pathParts.size - 1) {
                val folderName = pathParts[i]
                var folder = currentFolder.findFile(folderName)

                if (folder == null || !folder.isDirectory) {
                    folder = currentFolder.createDirectory(folderName) ?: return false
                }

                currentFolder = folder
            }

            val fileName = pathParts.last()
            val existingFile = currentFolder.findFile(fileName)

            val outputStream: OutputStream? = if (existingFile?.exists() == true) {
                // File exists - open it and truncate (overwrite)
                context.contentResolver.openOutputStream(existingFile.uri, "wt")
            } else {
                // File doesn't exist - create new
                val newFile = currentFolder.createFile(mimeType, fileName) ?: return false
                context.contentResolver.openOutputStream(newFile.uri)
            }

            outputStream?.use { output ->
                output.write(data)
            }

            return true
        } catch (e: Exception) {
            android.util.Log.e("FileOperations", "Error writing file", e)
            return false
        }
    }

    private fun getDocumentFileFromPath(filePath: String): DocumentFile? {
        val musicFolder = getMusicFolderDocumentFile() ?: return null

        val pathParts = filePath.split("/")
        var currentFolder = musicFolder

        // Navigate to parent folders
        for (i in 0 until pathParts.size - 1) {
            val folderName = pathParts[i]
            var folder = currentFolder.findFile(folderName)

            if (folder == null || !folder.isDirectory) {
                folder = currentFolder.createDirectory(folderName) ?: return null
            }

            currentFolder = folder
        }

        val fileName = pathParts.last()
        return currentFolder.findFile(fileName)
    }

    fun getExtensionFromContentType(contentType: String): String {
        val typeMap = mapOf(
            "audio/mpeg" to "mp3",
            "audio/mp3" to "mp3",
            "audio/flac" to "flac",
            "audio/x-flac" to "flac",
            "audio/alac" to "m4a",
            "audio/wav" to "wav",
            "audio/x-wav" to "wav",
            "audio/wave" to "wav",
            "audio/mp4" to "m4a",
            "audio/x-m4a" to "m4a",
            "audio/aac" to "aac"
        )

        val normalized = contentType.lowercase().split(";").first().trim()
        return typeMap[normalized] ?: "mp3"
    }

    fun sanitizeFilename(name: String): String {
        return name.replace(Regex("[/\\\\:*?\"<>|]"), "_")
    }

    fun generateTrackFilename(track: OwnToneApiClient.Track, extension: String): String {
        val artist = sanitizeFilename(track.artist)
        val album = sanitizeFilename(track.album)
        val trackId = track.id

        return "${artist}_${album}_$trackId.$extension"
    }
}