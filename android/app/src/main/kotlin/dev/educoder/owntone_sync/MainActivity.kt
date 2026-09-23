package dev.educoder.owntone_sync

import kotlinx.coroutines.*
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import android.content.ContentValues
import android.provider.MediaStore
import android.content.ContentUris
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import android.os.PowerManager
import java.util.concurrent.TimeUnit
import androidx.work.ExistingPeriodicWorkPolicy
import android.util.Log
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.ExistingWorkPolicy
import androidx.work.WorkInfo
import androidx.work.Data
import io.flutter.plugin.common.EventChannel
import android.content.Context
import com.squareup.moshi.Moshi
import com.squareup.moshi.JsonClass
import androidx.work.OutOfQuotaPolicy

class MainActivity: AudioServiceActivity() {
    private val EVENTS_CHANNEL = "dev.educoder.owntone_sync/events"
    private val STORAGE_CHANNEL = "dev.educoder.owntone_sync/storage"
    private val PROGRESS_CHANNEL = "dev.educoder.owntone_sync/sync_progress"
    private val SYNC_CHANNEL = "dev.educoder.owntone_sync/sync"
    private val PLAYER_CHANNEL = "dev.educoder.owntone_sync/player"
    private val REQUEST_CODE_MUSIC_FOLDER = 1001

    private var pendingMusicFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Events channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryOptimizationDisabled" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryOptimizationExemption" -> {
                    try {
                        Log.d("MainActivity", "Opening battery optimization settings")
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error opening battery optimization settings", e)
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Storage channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            // Run storage operations on background thread
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    when (call.method) {
                        "hasMusicFolderAccess" -> {
                            val hasAccess = hasMusicFolderAccess()
                            withContext(Dispatchers.Main) {
                                result.success(hasAccess)
                            }
                        }
                        "requestMusicFolderAccess" -> {
                            withContext(Dispatchers.Main) {
                                requestMusicFolderAccess(result)
                            }
                        }
                        "getMusicFolderUri" -> {
                            val uri = getMusicFolderUri()
                            withContext(Dispatchers.Main) {
                                result.success(uri)
                            }
                        }
                        "buildContentUri" -> {
                            val localPath = call.argument<String>("localPath")
                            result.success(
                                if (localPath != null) buildContentUri(localPath) else null
                            )
                        }
                        "buildContentUris" -> {
                            val localPaths = call.argument<List<String>>("localPaths") ?: emptyList()
                            result.success(localPaths.map { buildContentUri(it) })
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
                        else -> {
                            withContext(Dispatchers.Main) {
                                result.notImplemented()
                            }
                        }
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("EXCEPTION", e.message, null)
                    }
                }
            }
        }

        // Sync progress channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SyncProgressBroadcaster.eventSink = events
                    Log.d("MainActivity", "Progress listener attached")
                }

                override fun onCancel(arguments: Any?) {
                    SyncProgressBroadcaster.eventSink = null
                    Log.d("MainActivity", "Progress listener detached")
                }
            })

        // Add a new channel for sync control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerBackgroundSync" -> {
                    try {
                        // Check if a sync is already running
                        val workInfos = WorkManager.getInstance(applicationContext)
                            .getWorkInfosForUniqueWork("sync-task")
                            .get()

                        val isRunning = workInfos.any {
                            it.state == WorkInfo.State.RUNNING
                        }

                        if (isRunning) {
                            Log.d("MainActivity", "Sync already running, ignoring request")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        // Build the work request with expedited flag
                        val workRequest = OneTimeWorkRequestBuilder<BackgroundSyncWorker>()
                            .addTag("sync-task")
                            .setInputData(
                                Data.Builder()
                                    .putString("trigger_type", "manual")
                                    .build()
                            )
                            .apply {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                    setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                                }
                            }
                            .build()

                        // Replace any scheduled (but not running) sync with this immediate one
                        WorkManager.getInstance(applicationContext)
                            .enqueueUniqueWork(
                                "sync-task",
                                ExistingWorkPolicy.REPLACE,
                                workRequest
                            )

                        Log.d("MainActivity", "Manual sync triggered (expedited)")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error triggering sync", e)
                        result.error("SYNC_ERROR", e.message, null)
                    }
                }
                "cancelSync" -> {
                    WorkManager.getInstance(applicationContext)
                        .cancelAllWorkByTag("sync-task")
                    result.success(true)
                }
                "updateSyncSchedule" -> {
                    // Re-register worker when schedule changes
                    registerBackgroundSync()
                    result.success(true)
                }
                "isSyncRunning" -> {
                    try {
                        val workInfos = WorkManager.getInstance(applicationContext)
                            .getWorkInfosByTag("sync-task")
                            .get()
                        val isRunning = workInfos.any {
                            it.state == WorkInfo.State.RUNNING
                        }
                        Log.d("MainActivity", "Sync running check: $isRunning (found ${workInfos.size} work items, states: ${workInfos.map { it.state }})")
                        result.success(isRunning)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error checking sync state", e)
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Player channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "queueRebuild" -> {
                    try {
                        Log.d("MainActivity", "Received queue rebuild notification from sync worker")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error handling queue rebuild", e)
                        result.error("REBUILD_FAILED", e.message, null)
                    }
                }
                "recordPlayEvent" -> {
                    val trackId = call.argument<Int>("trackId")
                    val durationMs = call.argument<Int>("durationMs")
                    trackPlaybackEvent("play", trackId, durationMs ?: 0)
                    result.success(true)
                }
                "recordSkipEvent" -> {
                    val trackId = call.argument<Int>("trackId")
                    trackPlaybackEvent("skip", trackId, 0)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        registerBackgroundSync()

        // Clean up old work items periodically
        WorkManager.getInstance(applicationContext).pruneWork()

         // Create notification channel for sync worker
        SyncProgressBroadcaster.createNotificationChannel(applicationContext)

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

    private fun buildContentUri(localPath: String): String? {
        return buildContentUriFast(localPath) ?: buildContentUriWalk(localPath)
    }

    /// Builds the document URI directly from the tree URI plus the relative
    /// path, with no directory enumeration. Returns null so the caller can
    /// fall back to the (slow) walk.
    private fun buildContentUriFast(localPath: String): String? {
        val musicFolderUriString = getMusicFolderUri() ?: return null
        val relativePath = localPath.removePrefix("/")
        if (relativePath.isEmpty() || relativePath.contains("..")) return null
        return try {
            val treeUri = Uri.parse(musicFolderUriString)
            if (treeUri.pathSegments.size < 2 || treeUri.pathSegments[0] != "tree") {
                return null
            }
            // The document URI must be in the tree-scoped form
            // (.../tree/<treeDocId>/document/<treeDocId>/<relativePath>),
            // because the persisted grant from ACTION_OPEN_DOCUMENT_TREE only
            // authorises URIs that carry the tree. A bare /document/ URI is
            // what ACTION_OPEN_DOCUMENT produces and is denied with
            // SecurityException. buildDocumentUriUsingTree emits exactly the
            // tree-scoped form, with the document id encoded as a single
            // path segment. getTreeDocumentId (not lastPathSegment) extracts
            // the tree id: lastPathSegment breaks on a tree URI that already
            // carries a /document/ suffix.
            val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentId = treeDocId + "/" + relativePath
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId).toString()
        } catch (e: Exception) {
            Log.w("MainActivity", "Fast content URI build failed for: $localPath", e)
            null
        }
    }

    private fun buildContentUriWalk(localPath: String): String? {
        val musicFolderUriString = getMusicFolderUri() ?: return null
        return try {
            val musicFolder = DocumentFile.fromTreeUri(this, Uri.parse(musicFolderUriString))
            val pathParts = localPath.split("/")
            var currentFolder: DocumentFile? = musicFolder
            for (i in 0 until pathParts.size - 1) {
                val part = pathParts[i]
                val child = currentFolder?.findFile(part)
                if (child != null && child.isDirectory) {
                    currentFolder = child
                } else {
                    currentFolder = null
                    break
                }
            }
            val fileName = pathParts.last()
            currentFolder?.findFile(fileName)?.uri?.toString()
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to build content URI for: $localPath", e)
            null
        }
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

        // Path is already relative (e.g., "tracks/artist_album_123.mp3")
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

    private fun fileExists(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("INVALID_ARGUMENT", "File path is required", null)
            }
            return
        }

        val file = getDocumentFileFromPath(filePath)
        CoroutineScope(Dispatchers.Main).launch {
            result.success(file?.exists() == true)
        }
    }

    private fun getFileSize(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("INVALID_ARGUMENT", "File path is required", null)
            }
            return
        }

        val file = getDocumentFileFromPath(filePath)
        val size = if (file?.exists() == true) file.length() else 0
        CoroutineScope(Dispatchers.Main).launch {
            result.success(size)
        }
    }

    private fun deleteFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        if (filePath == null) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("INVALID_ARGUMENT", "File path is required", null)
            }
            return
        }

        try {
            val file = getDocumentFileFromPath(filePath)
            val deleted = file?.delete() ?: false
            CoroutineScope(Dispatchers.Main).launch {
                result.success(deleted)
            }
        } catch (e: Exception) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("DELETE_FAILED", e.message, null)
            }
        }
    }

    private fun writeFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("path")
        val data = call.argument<ByteArray>("data")

        if (filePath == null || data == null) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("INVALID_ARGUMENT", "File path and data are required", null)
            }
            return
        }

        try {
            val musicFolder = getMusicFolderDocumentFile()
            if (musicFolder == null) {
                CoroutineScope(Dispatchers.Main).launch {
                    result.error("NO_ACCESS", "Music folder access not granted", null)
                }
                return
            }

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

            // Path is already relative
            val pathParts = filePath.split("/")
            var currentFolder: DocumentFile = musicFolder

            // Navigate/create parent folders
            for (i in 0 until pathParts.size - 1) {
                val folderName = pathParts[i]
                var folder = currentFolder.findFile(folderName)

                if (folder == null || !folder.isDirectory) {
                    folder = currentFolder.createDirectory(folderName)
                    if (folder == null) {
                        CoroutineScope(Dispatchers.Main).launch {
                            result.error("CREATE_FAILED", "Could not create directory: $folderName", null)
                        }
                        return
                    }
                }

                currentFolder = folder
            }

            val fileName = pathParts.last()
            val existingFile = currentFolder.findFile(fileName)

            val outputStream: OutputStream? = if (existingFile?.exists() == true) {
                // File exists - open it and truncate (overwrite)
                contentResolver.openOutputStream(existingFile.uri, "wt")
            } else {
                // File doesn't exist - create new
                val newFile = currentFolder.createFile(mimeType, fileName)
                if (newFile == null) {
                    CoroutineScope(Dispatchers.Main).launch {
                        result.error("CREATE_FAILED", "Could not create file", null)
                    }
                    return
                }
                contentResolver.openOutputStream(newFile.uri)
            }

            outputStream?.use { output ->
                output.write(data)
            }

            CoroutineScope(Dispatchers.Main).launch {
                result.success(true)
            }
        } catch (e: Exception) {
            CoroutineScope(Dispatchers.Main).launch {
                result.error("WRITE_FAILED", e.message, null)
            }
        }
    }

    private fun trackPlaybackEvent(eventType: String, trackId: Int?, durationMs: Int) {
        if (trackId == null) {
            Log.d("MainActivity", "No track ID provided for event tracking")
            return
        }

        try {
            val db = openOrCreateDatabase("owntone_sync.db", Context.MODE_PRIVATE, null)
            val values = ContentValues().apply {
                put("track_id", trackId)
                put("event_type", eventType)
                put("timestamp", System.currentTimeMillis() / 1000)
                put("synced", 0)
            }

            val id = db.insert("pending_events", null, values)
            db.close()

            Log.d("MainActivity", "Recorded $eventType event for track $trackId (id=$id)")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error recording playback event", e)
        }
    }

    private fun registerBackgroundSync() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val syncScheduleJson = prefs.getString("flutter.sync_schedule", null)

        if (syncScheduleJson == null) {
            Log.d("MainActivity", "No sync schedule configured")
            return
        }

        try {
            val moshi = Moshi.Builder().build()
            val adapter = moshi.adapter(SyncSchedule::class.java)
            val schedule = adapter.fromJson(syncScheduleJson) ?: return

            if (!schedule.enabled) {
                // Cancel all work if sync is disabled
                WorkManager.getInstance(applicationContext).cancelAllWorkByTag("sync-task")
                Log.d("MainActivity", "Background sync disabled")
                return
            }

            // Calculate delay until next scheduled time
            val now = java.util.Calendar.getInstance()
            val scheduledTime = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, schedule.hour)
                set(java.util.Calendar.MINUTE, schedule.minute)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)

                // If scheduled time has passed today, schedule for tomorrow
                if (before(now)) {
                    add(java.util.Calendar.DAY_OF_MONTH, 1)
                }
            }

            val delayMillis = scheduledTime.timeInMillis - now.timeInMillis

            // Build constraints. Charging is deliberately NOT enforced here as
            // a WorkManager Constraint - see the comment at the top of
            // BackgroundSyncWorker.doWork() for why (trickle-charging near
            // 100% flips the OS "charging" signal on/off all night, which
            // would repeatedly stop/restart the worker). It's checked once,
            // "plugged in" rather than "actively charging", when the worker
            // starts instead.
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(
                    if (schedule.requiresWifi) NetworkType.UNMETERED else NetworkType.CONNECTED
                )
                .build()

            // Use OneTimeWorkRequest with calculated delay and expedited flag
            val syncWorkRequest = OneTimeWorkRequestBuilder<BackgroundSyncWorker>()
                .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
                .setConstraints(constraints)
                .addTag("sync-task")
                .apply {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                        setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                    }
                }
                .build()

            WorkManager.getInstance(applicationContext)
                .enqueueUniqueWork(
                    "sync-task",
                    ExistingWorkPolicy.REPLACE,
                    syncWorkRequest
                )

            Log.d("MainActivity", "Background sync scheduled for ${scheduledTime.time} (${delayMillis / 1000 / 60} minutes from now)")

            // Save expected sync time for missed sync detection
            prefs.edit().putString("flutter.expected_next_sync", scheduledTime.timeInMillis.toString()).apply()

        } catch (e: Exception) {
            Log.e("MainActivity", "Error registering background sync", e)
        }
    }

    @com.squareup.moshi.JsonClass(generateAdapter = true)
    data class SyncSchedule(
        val enabled: Boolean,
        val scheduleType: String,
        val hour: Int,
        val minute: Int,
        val daysOfWeek: List<Int>,
        val requiresCharging: Boolean,
        val requiresWifi: Boolean
    )

}