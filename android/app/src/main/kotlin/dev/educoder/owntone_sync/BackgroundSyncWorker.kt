package dev.educoder.owntone_sync

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.ExistingWorkPolicy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import com.squareup.moshi.Moshi
import com.squareup.moshi.JsonClass
import java.io.IOException

class BackgroundSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "BackgroundSyncWorker"
    }

    private suspend fun <T> loggedOperation(
        operation: String,
        block: suspend () -> T
    ): T {
        Log.d(TAG, "Starting: $operation")
        return try {
            val result = block()
            Log.d(TAG, "Completed: $operation")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed: $operation", e)
            throw SyncException("$operation failed: ${e.message}", e)
        }
    }

    private suspend fun <T> withTimeout(
        timeoutMs: Long,
        operationName: String,
        block: suspend () -> T
    ): T {
        return withContext(Dispatchers.IO) {
            try {
                kotlinx.coroutines.withTimeout(timeoutMs) {
                    block()
                }
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                throw SyncException("Timeout after ${timeoutMs}ms: $operationName")
            }
        }
    }

    private fun createInitialForegroundInfo(): ForegroundInfo {
        return SyncProgressBroadcaster.createForegroundInfo(
            applicationContext,
            id,  // worker.id
            currentPlaylist = "Initializing sync...",
            currentPlaylistIndex = 0,
            totalPlaylists = 1,
            downloadedTracks = 0,
            totalTracks = 0,
            currentTrackTitle = null,
            downloadProgress = null
        )
    }

    override suspend fun doWork(): Result {
        val worker = this@BackgroundSyncWorker
        val triggerType = inputData.getString("trigger_type") ?: "scheduled"
        val startTime = System.currentTimeMillis()

        // CRITICAL: Call setForeground IMMEDIATELY before any other work
        // This prevents WorkManager from killing the job on Android 12+
        try {
            setForeground(createInitialForegroundInfo())
            Log.i(TAG, "Foreground service started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service - sync cannot proceed", e)

            // If we can't start foreground service, we must fail immediately
            val errorMsg = if (
                android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
                e is android.app.ForegroundServiceStartNotAllowedException
            ) {
                "Cannot start sync: Foreground service not allowed (check app permissions and battery settings)"
            } else {
                "Cannot start sync: ${e.message}"
            }

            // Log failure to history
            try {
                val dbHelper = DatabaseHelper(applicationContext)
                dbHelper.insertSyncHistory(
                    DatabaseHelper.SyncHistoryRecord(
                        timestamp = System.currentTimeMillis(),
                        status = "failed",
                        playlistsSynced = 0,
                        tracksDownloaded = 0,
                        tracksDeleted = 0,
                        errorMessage = errorMsg,
                        durationMs = System.currentTimeMillis() - startTime,
                        triggerType = triggerType
                    )
                )
            } catch (dbError: Exception) {
                Log.e(TAG, "Failed to log foreground service failure", dbError)
            }

            SyncProgressBroadcaster.dismissNotification(applicationContext)
            SyncProgressBroadcaster.broadcastSyncComplete("failed", errorMsg)
            return Result.failure()
        }

        // Flag to track if we've already written history (prevent duplicates)
        var historyWritten = false

        return withContext(Dispatchers.IO) {
            try {
                Log.i(TAG, "=== SYNC WORKER STARTED ===")
                Log.i(TAG, "Worker ID: ${worker.id}")
                Log.i(TAG, "Run attempt: ${worker.runAttemptCount}")
                Log.i(TAG, "Tags: ${worker.tags}")
                Log.i(TAG, "Trigger type: $triggerType")

                SyncProgressBroadcaster.updateProgress(
                    applicationContext, worker, "Starting sync...", 0, 0, 0, 0
                )

            Log.i(TAG, "Starting background sync")

            // Get server URL from shared preferences
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            val serverUrl = prefs.getString("flutter.server_url", null)

            if (serverUrl == null) {
                Log.e(TAG, "No server URL configured")
                throw SyncException("No server URL configured")
            }

            // Initialize helpers
            val dbHelper = DatabaseHelper(applicationContext)
            val fileOps = FileOperations(applicationContext)
            val apiClient = OwnToneApiClient(serverUrl, fileOps)

            // Sync events first (if tracking is enabled)
            val eventTrackingEnabled = prefs.getBoolean("flutter.event_tracking_enabled", false)
            var eventsSynced = 0

            if (eventTrackingEnabled) {
                Log.i(TAG, "Event tracking enabled, syncing events first")
                eventsSynced = syncEvents(applicationContext, worker, apiClient, dbHelper)
            } else {
                Log.d(TAG, "Event tracking disabled, skipping event sync")
            }

            // Get selected playlist IDs - Flutter stores StringList with special encoding
            val playlistIdsString = prefs.getString("flutter.selected_playlist_ids", null)
            if (playlistIdsString == null || playlistIdsString.isEmpty()) {
                Log.i(TAG, "No playlists selected for sync")
                throw SyncException("No playlists selected for sync")
            }

            // Parse Flutter's StringList format: "prefix!["id1","id2"]"
            val playlistIds = try {
                val jsonPart = if (playlistIdsString.contains("!")) {
                    playlistIdsString.substringAfter("!")
                } else {
                    playlistIdsString
                }

                val moshi = Moshi.Builder().build()
                val adapter = moshi.adapter<Array<String>>(Array<String>::class.java)
                val list = adapter.fromJson(jsonPart) ?: emptyArray()
                list.map { it.toInt() }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing playlist IDs: $playlistIdsString", e)
                throw SyncException("Error parsing playlist IDs: $playlistIdsString", e)
            }

            if (playlistIds.isEmpty()) {
                Log.i(TAG, "No playlists selected for sync")
                throw SyncException("No playlists selected for sync")
            }

            var tracksDownloaded = 0
            var syncCancelled = false
            var cancellationReason: String? = null

            SyncProgressBroadcaster.updateProgress(
                applicationContext, worker, "Reading existing tracks", 0, playlistIds.size, 0, 0
            )

            // Get all existing files in tracks directory (one SAF call)
            val existingFiles = fileOps.getExistingFiles("tracks").toMutableSet()
            Log.d(TAG, "Found ${existingFiles.size} existing files in tracks directory")

            // Count total tracks first
            var totalTracks = 0
            for (playlistId in playlistIds) {
                try {
                    val tracksResponse = apiClient.getPlaylistTracks(playlistId)
                    totalTracks += tracksResponse.items.size
                } catch (e: Exception) {
                    Log.e(TAG, "Error counting tracks for playlist $playlistId", e)
                }
            }

            var tracksProcessed = 0;
            val playlistDetails = mutableListOf<Map<String, Any?>>()

            // Sync each playlist
            for ((playlistIndex, playlistId) in playlistIds.withIndex()) {
                // Check if work is cancelled
                if (isStopped) {
                    Log.i(TAG, "Sync cancelled by user")
                    syncCancelled = true
                    break
                }

                var playlistError: String? = null
                var playlistName = "Playlist $playlistId"
                var tracksInPlaylist = 0

                try {
                    Log.i(TAG, "Syncing playlist $playlistId")

                    // Fetch playlist metadata with timeout
                    val playlist = withTimeout(60000, "Fetching playlist metadata") {
                        val playlistsResponse = apiClient.getPlaylists()
                        playlistsResponse.items.find { it.id == playlistId }
                            ?: throw SyncException("Playlist $playlistId not found on server")
                    }

                    playlistName = playlist.name

                    // Update notification with playlist name
                    SyncProgressBroadcaster.updateProgress(
                        applicationContext, worker, "Validating playlist ${playlist.name}",
                        playlistIndex, playlistIds.size, tracksProcessed, totalTracks
                    )

                    // Fetch tracks for this playlist with timeout
                    val serverTracks = withTimeout(60000, "Fetching tracks for playlist ${playlist.name}") {
                        val tracksResponse = apiClient.getPlaylistTracks(playlistId)
                        tracksResponse.items
                    }

                    Log.i(TAG, "Playlist ${playlist.name} has ${serverTracks.size} tracks")

                    // Deduplicate tracks by ID (but keep original list for playlist_tracks table)
                    val uniqueTrackIds = serverTracks.map { it.id }.distinct()
                    val uniqueTracks = uniqueTrackIds.mapNotNull { trackId ->
                        serverTracks.find { it.id == trackId }
                    }

                    if (uniqueTracks.size < serverTracks.size) {
                        Log.d(TAG, "Deduplicated ${serverTracks.size} tracks to ${uniqueTracks.size} unique tracks")
                    }

                    tracksInPlaylist = serverTracks.size  // Original count for history

                    // Get existing tracks from database with timeout
                    val existingTracks = withTimeout(30000, "Querying database for existing tracks") {
                        dbHelper.getTracksByIds(uniqueTrackIds)
                    }

                    // Determine which tracks to download
                    val tracksToDownload = uniqueTracks.filter { track ->
                        val localTrack = existingTracks[track.id]
                        localTrack == null || !existingFiles.contains(localTrack.localPath)
                    }

                    Log.i(TAG, "Need to download ${tracksToDownload.size} tracks")

                    // Count already-validated tracks as processed
                    val alreadyValidatedCount = uniqueTracks.size - tracksToDownload.size
                    tracksProcessed += alreadyValidatedCount
                    Log.i(TAG, "${alreadyValidatedCount} tracks already on device")

                    // Download tracks
                    for (track in tracksToDownload) {
                        // Check if work is cancelled
                        if (isStopped) {
                            Log.i(TAG, "Sync cancelled, stopping downloads")
                            syncCancelled = true
                            cancellationReason = "Sync cancelled by user"
                            break
                        }

                        try {
                            // Download track with streaming
                            val downloadResult = apiClient.downloadTrack(
                                track,
                                onProgress = { bytesRead, totalBytes ->
                                    if (!isStopped) {
                                        try {
                                            val downloadProgress = if (totalBytes > 0) {
                                                (bytesRead.toDouble() / totalBytes.toDouble())
                                            } else {
                                                0.0
                                            }

                                            kotlinx.coroutines.runBlocking {
                                                SyncProgressBroadcaster.updateProgress(
                                                    applicationContext, worker, playlist.name,
                                                    playlistIndex, playlistIds.size,
                                                    tracksProcessed, totalTracks,
                                                    "Downloading ${track.title}", downloadProgress
                                                )
                                            }
                                        } catch (e: Exception) {
                                            Log.d(TAG, "Ignoring progress update error: ${e.message}")
                                        }
                                    }
                                },
                                isCancelled = { isStopped }
                            )

                            // Save to database
                            dbHelper.insertOrUpdateTrack(
                                DatabaseHelper.SyncedTrack(
                                    id = track.id,
                                    title = track.title,
                                    artist = track.artist,
                                    album = track.album,
                                    albumArtist = track.albumArtist,
                                    localPath = downloadResult.filePath,
                                    serverPath = track.path,
                                    downloadTimestamp = System.currentTimeMillis(),
                                    fileSize = downloadResult.bytesWritten,
                                    genre = track.genre ?: "",
                                    lengthMs = track.lengthMs,
                                    trackNumber = track.trackNumber,
                                    discNumber = track.discNumber,
                                    year = track.year,
                                    artworkUrl = track.artworkUrl ?: "",
                                    artworkPath = null
                                )
                            )

                            // Add to existingFiles set to prevent duplicate downloads
                            existingFiles.add(downloadResult.filePath)

                            tracksDownloaded++
                            tracksProcessed++
                            Log.i(TAG, "Downloaded track: ${track.title} (${downloadResult.bytesWritten} bytes)")

                        } catch (e: java.io.InterruptedIOException) {
                            Log.i(TAG, "Download cancelled by user")
                            syncCancelled = true
                            cancellationReason = "Cancelled by user"
                            break
                        } catch (e: StorageFullException) {
                            Log.e(TAG, "Storage full - cancelling sync", e)
                            syncCancelled = true
                            cancellationReason = e.message ?: "Storage full - not enough space to continue sync"
                            break
                        } catch (e: Exception) {
                            Log.e(TAG, "Error downloading track ${track.id} (${track.title})", e)
                            // Continue to next track
                        }
                    }

                    // Add all tracks to playlist relationship (including duplicates from original list)
                    dbHelper.clearPlaylistTracks(playlistId)
                    for (track in serverTracks) {  // Use original list with duplicates
                        dbHelper.addTrackToPlaylist(playlistId, track.id)
                    }

                    // Update playlist metadata
                    dbHelper.insertOrUpdatePlaylist(
                        DatabaseHelper.SyncedPlaylist(
                            id = playlist.id,
                            name = playlist.name,
                            path = playlist.path,
                            type = playlist.type,
                            lastSynced = System.currentTimeMillis()
                        )
                    )

                    // Generate playlist file
                    generatePlaylistFile(playlist, serverTracks, dbHelper, fileOps)

                } catch (e: SyncException) {
                    Log.e(TAG, "Error syncing playlist $playlistId: ${e.message}", e)
                    playlistError = e.message
                } catch (e: Exception) {
                    Log.e(TAG, "Error syncing playlist $playlistId", e)
                    playlistError = "Unexpected error: ${e.message ?: e.javaClass.simpleName}"
                }

                // Record playlist in history (success or failure)
                playlistDetails.add(mapOf<String, Any?>(
                    "playlist_id" to playlistId,
                    "playlist_name" to playlistName,
                    "tracks_in_playlist" to tracksInPlaylist,
                    "error_message" to playlistError
                ))
            }

            var tracksDeleted = 0
            val deleteOrphanedFiles = prefs.getBoolean("flutter.delete_orphaned_files", false)

            if (deleteOrphanedFiles && !syncCancelled) {
                Log.i(TAG, "Checking for orphaned files...")

                // Get all track IDs that are in any synced playlist
                val allSyncedTrackIds = mutableSetOf<Int>()
                for (playlistId in playlistIds) {
                    val trackIds = dbHelper.getTracksForPlaylist(playlistId)
                    allSyncedTrackIds.addAll(trackIds.map { it.id })
                }

                // Get all tracks in the database
                val allLocalTracks = dbHelper.getAllTracks()

                // Find orphans: tracks in DB but not in any synced playlist
                val orphanedTracks = allLocalTracks.filter { it.id !in allSyncedTrackIds }

                Log.i(TAG, "Found ${orphanedTracks.size} orphaned tracks")

                // Batch delete orphaned files
                val orphanedPaths = orphanedTracks.map { it.localPath }
                val deleteResult = fileOps.deleteFiles(
                    filePaths = orphanedPaths,
                    onProgress = { deleted, total ->
                        // Update progress during deletion
                        runBlocking {
                            SyncProgressBroadcaster.updateProgress(
                                applicationContext, worker,
                                "Deleting orphaned files",
                                playlistIds.size, playlistIds.size,
                                deleted, total,
                                "Deleted $deleted of $total files",
                                deleted.toDouble() / total
                            )
                        }
                    },
                    isCancelled = { isStopped }
                )

                // Remove successfully deleted tracks from database
                val successfullyDeletedPaths = orphanedPaths.toSet() - deleteResult.failedPaths.toSet()
                for (track in orphanedTracks) {
                    if (successfullyDeletedPaths.contains(track.localPath)) {
                        dbHelper.deleteTrack(track.id)
                        tracksDeleted++
                    }
                }

                if (deleteResult.failedPaths.isNotEmpty()) {
                    Log.w(TAG, "Failed to delete ${deleteResult.failedPaths.size} orphaned files")
                    deleteResult.failedPaths.take(10).forEach { path ->
                        Log.w(TAG, "  Failed: $path")
                    }
                    if (deleteResult.failedPaths.size > 10) {
                        Log.w(TAG, "  ... and ${deleteResult.failedPaths.size - 10} more")
                    }
                }

                Log.i(TAG, "Deleted $tracksDeleted orphaned tracks")
            }

            val duration = System.currentTimeMillis() - startTime

            // Log sync history
            val syncId = dbHelper.insertSyncHistory(
                DatabaseHelper.SyncHistoryRecord(
                    timestamp = System.currentTimeMillis(),
                    status = if (syncCancelled) "cancelled" else "success",
                    playlistsSynced = playlistIds.size,
                    tracksDownloaded = tracksDownloaded,
                    tracksDeleted = tracksDeleted,
                    errorMessage = if (syncCancelled) cancellationReason else null,
                    durationMs = duration,
                    triggerType = triggerType
                )
            )
            historyWritten = true

            // Insert playlist details
            for (detail in playlistDetails) {
                dbHelper.insertSyncHistoryPlaylist(
                    DatabaseHelper.SyncHistoryPlaylist(
                        syncId = syncId.toInt(),
                        playlistId = detail["playlist_id"] as Int,
                        playlistName = detail["playlist_name"] as String,
                        tracksInPlaylist = detail["tracks_in_playlist"] as Int,
                        errorMessage = detail["error_message"] as String?
                    )
                )
            }

            // Schedule next sync
            scheduleNextSync()

            Log.i(TAG, "Background sync completed: $tracksDownloaded tracks downloaded in ${duration}ms")
            if (syncCancelled) {
                SyncProgressBroadcaster.dismissNotification(applicationContext)
                SyncProgressBroadcaster.broadcastSyncComplete(
                    "cancelled",
                    cancellationReason ?: "Sync cancelled by user"
                )
            } else {
                SyncProgressBroadcaster.dismissNotification(applicationContext)
                SyncProgressBroadcaster.broadcastSyncComplete("success")
            }

            Result.success()

        } catch (e: CancellationException) {
                val duration = System.currentTimeMillis() - startTime

                val wasUserCancelled = isStopped
                val status = if (wasUserCancelled) "cancelled" else "failed"
                val errorMessage = if (wasUserCancelled) {
                    "Cancelled by user"
                } else {
                    "Sync interrupted by system: ${e.message ?: "Job was cancelled"}"
                }

                Log.w(TAG, "Sync $status: $errorMessage", e)

                if (!historyWritten) {
                    try {
                        val dbHelper = DatabaseHelper(applicationContext)
                        dbHelper.insertSyncHistory(
                            DatabaseHelper.SyncHistoryRecord(
                                timestamp = System.currentTimeMillis(),
                                status = status,
                                playlistsSynced = 0,
                                tracksDownloaded = 0,
                                tracksDeleted = 0,
                                errorMessage = errorMessage,
                                durationMs = duration,
                                triggerType = triggerType
                            )
                        )
                        historyWritten = true
                    } catch (dbError: Exception) {
                        Log.e(TAG, "Failed to log cancellation to database", dbError)
                    }
                }

                SyncProgressBroadcaster.dismissNotification(applicationContext)
                SyncProgressBroadcaster.broadcastSyncComplete(status, errorMessage)

                if (wasUserCancelled) Result.success() else Result.failure()

            } catch (e: Exception) {
                val duration = System.currentTimeMillis() - startTime
                Log.e(TAG, "Background sync failed with exception", e)

                val errorMessage = when (e) {
                    is SyncException -> e.message ?: "Sync error"
                    is StorageFullException -> e.message ?: "Storage full"
                    is IOException -> "Network or I/O error: ${e.message}"
                    else -> "Unexpected error: ${e.message ?: e.javaClass.simpleName}"
                }

                if (!historyWritten) {
                    try {
                        val dbHelper = DatabaseHelper(applicationContext)
                        dbHelper.insertSyncHistory(
                            DatabaseHelper.SyncHistoryRecord(
                                timestamp = System.currentTimeMillis(),
                                status = "failed",
                                playlistsSynced = 0,
                                tracksDownloaded = 0,
                                tracksDeleted = 0,
                                errorMessage = errorMessage,
                                durationMs = duration,
                                triggerType = triggerType
                            )
                        )
                        historyWritten = true
                    } catch (dbError: Exception) {
                        Log.e(TAG, "Failed to log sync failure to database", dbError)
                    }
                }

                SyncProgressBroadcaster.dismissNotification(applicationContext)
                SyncProgressBroadcaster.broadcastSyncComplete("failed", errorMessage)
                Result.failure()
            }
        }
    }

    private fun generatePlaylistFile(
        playlist: OwnToneApiClient.Playlist,
        tracks: List<OwnToneApiClient.Track>,
        dbHelper: DatabaseHelper,
        fileOps: FileOperations
    ) {
        try {
            val buffer = StringBuilder()
            buffer.append("#EXTM3U\n")
            buffer.append("#PLAYLIST:${playlist.name}\n")
            buffer.append("#EXTENC:UTF-8\n")

            for (track in tracks) {
                val localTrack = dbHelper.getTrackById(track.id)
                if (localTrack != null) {
                    val duration = track.lengthMs / 1000
                    buffer.append("#EXTINF:$duration,${track.artist} - ${track.title}\n")

                    // Make path relative to playlists folder
                    val relativePath = "../${localTrack.localPath}"
                    buffer.append("$relativePath\n")
                }
            }

            val sanitizedName = fileOps.sanitizeFilename(playlist.name)
            val playlistPath = "playlists/$sanitizedName.m3u"

            val content = buffer.toString()
            fileOps.writeFile(playlistPath, content.toByteArray(Charsets.UTF_8))

            Log.i(TAG, "Generated playlist file: $playlistPath")
        } catch (e: Exception) {
            Log.e(TAG, "Error generating playlist file", e)
        }
    }

    private fun scheduleNextSync() {
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        val syncScheduleJson = prefs.getString("flutter.sync_schedule", null) ?: return

        try {
            val moshi = Moshi.Builder().build()
            val adapter = moshi.adapter(SyncSchedule::class.java)
            val schedule = adapter.fromJson(syncScheduleJson) ?: return

            if (!schedule.enabled) return

            // Calculate delay until next scheduled time (tomorrow)
            val now = java.util.Calendar.getInstance()
            val scheduledTime = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, schedule.hour)
                set(java.util.Calendar.MINUTE, schedule.minute)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
                add(java.util.Calendar.DAY_OF_MONTH, 1) // Tomorrow
            }

            val delayMillis = scheduledTime.timeInMillis - now.timeInMillis

            val constraints = androidx.work.Constraints.Builder()
                .setRequiredNetworkType(
                    if (schedule.requiresWifi) androidx.work.NetworkType.UNMETERED
                    else androidx.work.NetworkType.CONNECTED
                )
                .setRequiresCharging(schedule.requiresCharging)
                .build()

            val syncWorkRequest = androidx.work.OneTimeWorkRequestBuilder<BackgroundSyncWorker>()
                .setInitialDelay(delayMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
                .setConstraints(constraints)
                .addTag("sync-task")
                .build()

            WorkManager.getInstance(applicationContext)
                .enqueueUniqueWork(
                    "sync-task",
                    androidx.work.ExistingWorkPolicy.REPLACE,
                    syncWorkRequest
                )

            Log.d(TAG, "Next sync scheduled for ${scheduledTime.time}")

            // Save expected sync time for missed sync detection
            prefs.edit().putString("flutter.expected_next_sync", scheduledTime.timeInMillis.toString()).apply()

        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling next sync", e)
        }
    }

    private suspend fun syncEvents(
        context: Context,
        worker: CoroutineWorker,
        apiClient: OwnToneApiClient,
        dbHelper: DatabaseHelper
    ): Int {
        val unsyncedEvents = dbHelper.getUnsyncedEvents()

        if (unsyncedEvents.isEmpty()) {
            Log.d(TAG, "No events to sync")
            return 0
        }

        Log.i(TAG, "Syncing ${unsyncedEvents.size} events")

        // Group events by track_id
        val eventsByTrack = unsyncedEvents.groupBy { it.trackId }
        var eventsSynced = 0
        var eventsDeleted = 0
        var trackIndex = 0

        for ((trackId, events) in eventsByTrack) {
            trackIndex++

            // Update progress
            SyncProgressBroadcaster.updateProgress(
                context, worker,
                "Syncing playback events",
                0, 1,
                trackIndex, eventsByTrack.size,
                "Track $trackId",
                trackIndex.toDouble() / eventsByTrack.size
            )

            try {
                // Accumulate counts and find most recent timestamps
                var playCount = 0
                var skipCount = 0
                var mostRecentTimePlayed: Long? = null
                var mostRecentTimeSkipped: Long? = null

                for (event in events) {
                    when (event.eventType) {
                        "play" -> {
                            playCount++
                            if (mostRecentTimePlayed == null || event.timestamp > mostRecentTimePlayed) {
                                mostRecentTimePlayed = event.timestamp
                            }
                        }
                        "skip" -> {
                            skipCount++
                            if (mostRecentTimeSkipped == null || event.timestamp > mostRecentTimeSkipped) {
                                mostRecentTimeSkipped = event.timestamp
                            }
                        }
                    }
                }

                Log.d(TAG, "Syncing track $trackId: +$playCount plays, +$skipCount skips")

                // Update track stats on server
                apiClient.updateTrackStats(
                    trackId,
                    additionalPlayCount = playCount,
                    additionalSkipCount = skipCount,
                    mostRecentTimePlayed = mostRecentTimePlayed,
                    mostRecentTimeSkipped = mostRecentTimeSkipped
                )

                // Success - delete these events
                val eventIds = events.map { it.id }
                dbHelper.deleteEvents(eventIds)
                eventsSynced += events.size

                Log.i(TAG, "Successfully synced ${events.size} events for track $trackId")

            } catch (e: Exception) {
                Log.e(TAG, "Failed to sync events for track $trackId", e)

                // Increment retry count for all events in this batch
                for (event in events) {
                    val newRetryCount = event.retryCount + 1

                    if (newRetryCount >= 5) {
                        // Max retries reached - delete the event
                        dbHelper.deleteEvent(event.id)
                        eventsDeleted++
                        Log.w(TAG, "Deleted event ${event.id} after $newRetryCount retries")
                    } else {
                        // Increment retry count
                        dbHelper.incrementRetryCount(event.id)
                    }
                }
            }
        }

        if (eventsDeleted > 0) {
            Log.i(TAG, "Deleted $eventsDeleted events after max retries")
        }

        Log.i(TAG, "Event sync completed: $eventsSynced events synced, $eventsDeleted events deleted")
        return eventsSynced
    }

    @com.squareup.moshi.JsonClass(generateAdapter = true)
    data class SyncSchedule(
        val enabled: Boolean,
        val hour: Int,
        val minute: Int,
        val requiresCharging: Boolean,
        val requiresWifi: Boolean
    )

}

class SyncException(message: String, cause: Throwable? = null) : Exception(message, cause)