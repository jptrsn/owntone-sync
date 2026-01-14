package dev.educoder.owntone_sync

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import java.io.OutputStream
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicInteger
import android.system.ErrnoException
import android.system.OsConstants
import java.io.IOException
import java.io.InputStream

class FileOperations(private val context: Context) {

    companion object {
        private const val STREAM_BUFFER_SIZE = 262144 // 256KB
    }

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

    /**
     * Writes a file by streaming from an InputStream directly to SAF storage.
     * This avoids loading the entire file into memory.
     *
     * @param filePath Relative path (e.g., "tracks/filename.flac")
     * @param inputStream Source stream to read from
     * @param contentType MIME type for the file
     * @param expectedSize Expected number of bytes (from Content-Length)
     * @param onProgress Called after each chunk is written
     * @return Number of bytes actually written
     * @throws StorageFullException if storage is full
     * @throws IOException for other I/O errors
     */
    fun writeFileStreaming(
        filePath: String,
        inputStream: InputStream,
        contentType: String,
        expectedSize: Long,
        onProgress: (written: Long, total: Long) -> Unit,
        isCancelled: () -> Boolean
    ): Long {
        var bytesWritten = 0L
        var outputStream: OutputStream? = null

        try {
            // Determine which folder this file goes in
            val pathParts = filePath.split("/")
            if (pathParts.size < 2) {
                throw IOException("Invalid file path: $filePath")
            }

            val folderType = pathParts[0] // "tracks" or "playlists"
            val fileName = pathParts.last()

            // Get the appropriate cached folder
            val parentFolder = when (folderType) {
                "tracks" -> getTracksFolder()
                "playlists" -> getPlaylistsFolder()
                else -> throw IOException("Unknown folder type: $folderType")
            } ?: throw IOException("Unable to access parent folder")

            // Determine MIME type from content type
            val mimeType = contentType.split(";").first().trim()

            // Check if file already exists and delete it (we're rewriting)
            val existingFile = parentFolder.findFile(fileName)
            if (existingFile?.exists() == true) {
                existingFile.delete()
            }

            // Create new file
            val newFile = parentFolder.createFile(mimeType, fileName)
                ?: throw IOException("Unable to create file: $fileName")

            // Open output stream
            outputStream = context.contentResolver.openOutputStream(newFile.uri)
                ?: throw IOException("Unable to open output stream for: $fileName")

            // Stream data with buffering
            val buffer = ByteArray(STREAM_BUFFER_SIZE)
            var bytesRead: Int
            var lastProgressUpdate = 0L

            inputStream.use { input ->
                java.io.BufferedOutputStream(outputStream, STREAM_BUFFER_SIZE).use { output ->
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        // Check for cancellation
                        if (isCancelled()) {
                            Log.i("FileOperations", "Download cancelled by user, stopping stream")
                            throw java.io.InterruptedIOException("Download cancelled by user")
                        }

                        output.write(buffer, 0, bytesRead)
                        bytesWritten += bytesRead

                        val now = System.currentTimeMillis()
                        if (now - lastProgressUpdate >= 50) {
                            lastProgressUpdate = now
                            onProgress(bytesWritten, expectedSize)
                        }
                    }
                    output.flush()
                }
            }

            // Validate file size
            if (bytesWritten != expectedSize) {
                // Size mismatch - delete the file
                deleteFile(filePath)
                throw IOException(
                    "Download failed: file size mismatch (expected $expectedSize, got $bytesWritten)"
                )
            }

            Log.i("FileOperations", "Successfully streamed $bytesWritten bytes to $filePath")
            return bytesWritten

        } catch (e: IOException) {
            // Clean up partial file
            try {
                deleteFile(filePath)
                Log.w("FileOperations", "Deleted partial file after error: $filePath")
            } catch (deleteError: Exception) {
                Log.e("FileOperations", "Failed to delete partial file: $filePath", deleteError)
            }

            // Check if storage is full
            if (isStorageFull(e)) {
                throw StorageFullException(
                    "Storage full - unable to write file (wrote $bytesWritten of $expectedSize bytes)",
                    e
                )
            }

            // Rethrow original exception
            throw e
        } finally {
            // Ensure output stream is closed
            outputStream?.close()
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

    /**
     * Detects if an IOException is due to storage being full
     */
    private fun isStorageFull(e: IOException): Boolean {
        // Check message for common "no space" patterns
        val msg = e.message?.lowercase() ?: ""
        if (msg.contains("no space left on device") || msg.contains("enospc")) {
            return true
        }

        // Check for ENOSPC errno (more reliable on modern Android)
        val cause = e.cause
        if (cause is ErrnoException && cause.errno == OsConstants.ENOSPC) {
            return true
        }

        return false
    }

}

/**
 * Exception thrown when storage is full during file operations
 */
class StorageFullException(message: String, cause: Throwable? = null)
    : IOException(message, cause)