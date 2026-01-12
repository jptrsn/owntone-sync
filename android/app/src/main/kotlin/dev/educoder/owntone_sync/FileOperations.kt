package dev.educoder.owntone_sync

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import java.io.OutputStream
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicInteger

class FileOperations(private val context: Context) {

    data class BatchDeleteResult(
        val totalFiles: Int,
        val successCount: Int,
        val failedPaths: List<String>
    )

    // Cache commonly used folders
    private var cachedTracksFolder: DocumentFile? = null
    private var cachedPlaylistsFolder: DocumentFile? = null

    // Cache invalidation
    fun invalidateCache() {
        cachedTracksFolder = null
        cachedPlaylistsFolder = null
    }

    // Get or create tracks folder once
    private fun getTracksFolder(): DocumentFile? {
        if (cachedTracksFolder != null && cachedTracksFolder!!.exists()) {
            return cachedTracksFolder
        }

        val musicFolder = getMusicFolderDocumentFile() ?: return null

        var tracksFolder = musicFolder.findFile("tracks")
        if (tracksFolder == null) {
            tracksFolder = musicFolder.createDirectory("tracks")
        } else if (!tracksFolder.isDirectory) {
            Log.w("FileOperations", "tracks exists as file, deleting")
            tracksFolder.delete()
            tracksFolder = musicFolder.createDirectory("tracks")
        }

        cachedTracksFolder = tracksFolder
        return tracksFolder
    }

    // Get or create playlists folder once
    private fun getPlaylistsFolder(): DocumentFile? {
        if (cachedPlaylistsFolder != null && cachedPlaylistsFolder!!.exists()) {
            return cachedPlaylistsFolder
        }

        val musicFolder = getMusicFolderDocumentFile() ?: return null

        var playlistsFolder = musicFolder.findFile("playlists")
        if (playlistsFolder == null) {
            playlistsFolder = musicFolder.createDirectory("playlists")
        } else if (!playlistsFolder.isDirectory) {
            Log.w("FileOperations", "playlists exists as file, deleting")
            playlistsFolder.delete()
            playlistsFolder = musicFolder.createDirectory("playlists")
        }

        cachedPlaylistsFolder = playlistsFolder
        return playlistsFolder
    }

    fun getMusicFolderUri(): String? {
        return context.getSharedPreferences("storage_prefs", Context.MODE_PRIVATE)
            .getString("music_folder_uri", null)
    }

    private fun getMusicFolderDocumentFile(): DocumentFile? {
        val uriString = getMusicFolderUri() ?: return null
        val uri = Uri.parse(uriString)
        return DocumentFile.fromTreeUri(context, uri)
    }

    fun getExistingFiles(directoryPath: String): Set<String> {
        try {
            val musicFolder = getMusicFolderDocumentFile() ?: return emptySet()

            // Navigate to the directory
            val pathParts = directoryPath.split("/")
            var currentFolder = musicFolder

            for (folderName in pathParts) {
                if (folderName.isEmpty()) continue
                val folder = currentFolder.findFile(folderName)
                if (folder == null || !folder.isDirectory) {
                    return emptySet()
                }
                currentFolder = folder
            }

            // Get all files in this directory
            val existingFiles = mutableSetOf<String>()
            currentFolder.listFiles().forEach { file ->
                if (file.isFile) {
                    existingFiles.add("$directoryPath/${file.name}")
                }
            }

            return existingFiles
        } catch (e: Exception) {
            android.util.Log.e("FileOperations", "Error getting existing files", e)
            return emptySet()
        }
    }

    fun fileExists(filePath: String): Boolean {
        val file = getDocumentFileFromPath(filePath)
        return file?.exists() == true
    }

    fun writeFile(filePath: String, data: ByteArray): Boolean {
        try {
            // Determine which folder this file goes in
            val pathParts = filePath.split("/")
            if (pathParts.size < 2) return false

            val folderType = pathParts[0] // "tracks" or "playlists"
            val fileName = pathParts.last()

            // Get the appropriate cached folder
            val parentFolder = when (folderType) {
                "tracks" -> getTracksFolder()
                "playlists" -> getPlaylistsFolder()
                else -> {
                    Log.e("FileOperations", "Unknown folder type: $folderType")
                    return false
                }
            } ?: return false

            // Determine MIME type from extension
            val extension = fileName.substringAfterLast('.', "")
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

            // Check if file already exists
            val existingFile = parentFolder.findFile(fileName)

            val outputStream: OutputStream? = if (existingFile?.exists() == true) {
                context.contentResolver.openOutputStream(existingFile.uri, "wt")
            } else {
                val newFile = parentFolder.createFile(mimeType, fileName) ?: return false
                context.contentResolver.openOutputStream(newFile.uri)
            }

            outputStream?.use { output ->
                java.io.BufferedOutputStream(output, 262144).use { buffered ->
                    buffered.write(data)
                    buffered.flush()
                }
            }

            return true
        } catch (e: Exception) {
            android.util.Log.e("FileOperations", "Error writing file", e)
            return false
        }
    }

    private fun getDocumentFileFromPath(filePath: String): DocumentFile? {
        val pathParts = filePath.split("/")
        if (pathParts.size < 2) return null

        val folderType = pathParts[0]
        val fileName = pathParts.last()

        val parentFolder = when (folderType) {
            "tracks" -> getTracksFolder()
            "playlists" -> getPlaylistsFolder()
            else -> return null
        } ?: return null

        return parentFolder.findFile(fileName)
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
        val title = sanitizeFilename(track.title)
        val artist = sanitizeFilename(track.artist)
        val album = sanitizeFilename(track.album)
        val trackId = track.id

        return "${artist}_${title}_${album}_$trackId.$extension"
    }

    fun deleteFile(filePath: String): Boolean {
        return try {
            val file = getDocumentFileFromPath(filePath)
            file?.delete() ?: false
        } catch (e: Exception) {
            android.util.Log.e("FileOperations", "Error deleting file: $filePath", e)
            false
        }
    }

    suspend fun deleteFiles(
        filePaths: List<String>,
        onProgress: ((deleted: Int, total: Int) -> Unit)? = null,
        isCancelled: () -> Boolean = { false }
    ): BatchDeleteResult = withContext(Dispatchers.IO) {
        val total = filePaths.size
        val failures = mutableListOf<String>()
        val deletedCount = AtomicInteger(0)
        val concurrencyLimit = 50

        Log.i("FileOperations", "Starting batch delete of $total files with concurrency limit $concurrencyLimit")

        // Process files in chunks to limit concurrency
        for (chunk in filePaths.chunked(concurrencyLimit)) {
            // Check for cancellation before processing each chunk
            if (isCancelled()) {
                Log.i("FileOperations", "Batch delete cancelled after ${deletedCount.get()} deletions")
                break
            }

            chunk.map { path ->
                async {
                    try {
                        val success = deleteFile(path)
                        if (success) {
                            val current = deletedCount.incrementAndGet()
                            // Report progress every 10 deletions
                            if (current % 10 == 0 || current == total) {
                                onProgress?.invoke(current, total)
                            }
                        } else {
                            synchronized(failures) {
                                failures.add(path)
                            }
                            Log.w("FileOperations", "Failed to delete file: $path")
                        }
                        success
                    } catch (e: Exception) {
                        synchronized(failures) {
                            failures.add(path)
                        }
                        Log.e("FileOperations", "Exception deleting file: $path", e)
                        false
                    }
                }
            }.awaitAll()
        }

        val finalCount = deletedCount.get()
        val wasCancelled = isCancelled()
        Log.i("FileOperations", "Batch delete ${if (wasCancelled) "cancelled" else "completed"}: $finalCount/$total succeeded, ${failures.size} failed")

        BatchDeleteResult(
            totalFiles = total,
            successCount = finalCount,
            failedPaths = failures
        )
    }

}