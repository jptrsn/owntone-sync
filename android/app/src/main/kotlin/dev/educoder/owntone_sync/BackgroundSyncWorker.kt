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

class BackgroundSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "BackgroundSyncWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val worker = this@BackgroundSyncWorker
        try {

            SyncProgressBroadcaster.updateProgress(
                applicationContext, worker, "Starting sync...", 0, 0, 0, 0
            )

            Log.i(TAG, "Starting background sync")

            // Get trigger type from input data (default to "scheduled")
            val triggerType = inputData.getString("trigger_type") ?: "scheduled"

            // Get server URL from shared preferences
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            val serverUrl = prefs.getString("flutter.server_url", null)

            if (serverUrl == null) {
                Log.e(TAG, "No server URL configured")
                return@withContext Result.failure()
            }

            // Get selected playlist IDs - Flutter stores StringList with special encoding
            val playlistIdsString = prefs.getString("flutter.selected_playlist_ids", null)
            if (playlistIdsString == null || playlistIdsString.isEmpty()) {
                Log.i(TAG, "No playlists selected for sync")
                return@withContext Result.success()
            }

            // Parse Flutter's StringList format: "prefix!["id1","id2"]"
            val playlistIds = try {
                val jsonPart = if (playlistIdsString.contains("!")) {
                    playlistIdsString.substringAfter("!")
                } else {
                    playlistIdsString
                }

                val gson = com.google.gson.Gson()
                val list = gson.fromJson(jsonPart, Array<String>::class.java)
                list.map { it.toInt() }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing playlist IDs: $playlistIdsString", e)
                return@withContext Result.failure()
            }

            if (playlistIds.isEmpty()) {
                Log.i(TAG, "No playlists selected for sync")
                return@withContext Result.success()
            }

            // Initialize helpers
            val apiClient = OwnToneApiClient(serverUrl)
            val dbHelper = DatabaseHelper(applicationContext)
            val fileOps = FileOperations(applicationContext)

            val startTime = System.currentTimeMillis()
            var tracksDownloaded = 0
            var syncCancelled = false

            SyncProgressBroadcaster.updateProgress(
                applicationContext, worker, "Reading existing tracks", 0, playlistIds.size, 0, 0
            )

            // Get all existing files in tracks directory (one SAF call)
            val existingFiles = fileOps.getExistingFiles("tracks")
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

            // Sync each playlist
            for ((playlistIndex, playlistId) in playlistIds.withIndex()) {
                // Check if work is cancelled
                if (isStopped) {
                    Log.i(TAG, "Sync cancelled by user")
                    syncCancelled = true
                    break
                }
                try {
                    Log.i(TAG, "Syncing playlist $playlistId")

                    // Fetch playlist metadata
                    val playlistsResponse = apiClient.getPlaylists()
                    val playlist = playlistsResponse.items.find { it.id == playlistId }

                    if (playlist == null) {
                        Log.w(TAG, "Playlist $playlistId not found on server")
                        continue
                    }

                    // Update notification with playlist name
                    SyncProgressBroadcaster.updateProgress(
                        applicationContext, worker, "Validating playlist ${playlist.name}", playlistIndex, playlistIds.size, tracksDownloaded, totalTracks
                    )

                    // Fetch tracks for this playlist
                    val tracksResponse = apiClient.getPlaylistTracks(playlistId)
                    val serverTracks = tracksResponse.items

                    Log.i(TAG, "Playlist ${playlist.name} has ${serverTracks.size} tracks")

                    // Get existing tracks from database
                    val serverTrackIds = serverTracks.map { it.id }
                    val existingTracks = dbHelper.getTracksByIds(serverTrackIds)

                    // Determine which tracks to download
                    val tracksToDownload = serverTracks.filter { track ->
                        val localTrack = existingTracks[track.id]
                        localTrack == null || !existingFiles.contains(localTrack.localPath)
                    }

                    Log.i(TAG, "Need to download ${tracksToDownload.size} tracks")

                    // Download tracks
                    for (track in tracksToDownload) {
                        // Check if work is cancelled
                        if (isStopped) {
                            Log.i(TAG, "Sync cancelled, stopping downloads")
                            syncCancelled = true
                            break
                        }
                        try {
                            // Update notification for current track
                            SyncProgressBroadcaster.updateProgress(
                                applicationContext, worker, playlist.name, playlistIndex, playlistIds.size, tracksDownloaded, totalTracks,
                                track.title, 0.0
                            )

                            // Download track data and get content type with progress tracking
                            val downloadStart = System.currentTimeMillis()
                            val (trackData, contentType) = apiClient.downloadTrack(track.id) { bytesRead, totalBytes ->
                                if (!isStopped) {
                                    try {
                                        val downloadProgress = if (totalBytes > 0) (bytesRead.toDouble() / totalBytes.toDouble()) else 0.0

                                        kotlinx.coroutines.runBlocking {
                                            SyncProgressBroadcaster.updateProgress(
                                                applicationContext, worker, playlist.name, playlistIndex, playlistIds.size,
                                                tracksDownloaded, totalTracks,
                                                "Downloading ${track.title}", downloadProgress
                                            )
                                        }
                                    } catch (e: Exception) {
                                        Log.d(TAG, "Ignoring progress update error during cancellation: ${e.message}")
                                    }
                                }
                            }

                            val downloadTime = System.currentTimeMillis() - downloadStart
                            Log.i(TAG, "Download took ${downloadTime}ms for ${trackData.size} bytes (${track.title})")


                            val extension = fileOps.getExtensionFromContentType(contentType)

                            // Generate file path
                            val filename = fileOps.generateTrackFilename(track, extension)
                            val filePath = "tracks/$filename"

                            kotlinx.coroutines.runBlocking {
                                            SyncProgressBroadcaster.updateProgress(
                                                applicationContext, worker, playlist.name, playlistIndex, playlistIds.size,
                                                tracksDownloaded, totalTracks,
                                                "Saving ${track.title}", 1.0
                                            )
                                        }
                            val writeStart = System.currentTimeMillis()
                            val success = fileOps.writeFile(filePath, trackData)

                            val writeTime = System.currentTimeMillis() - writeStart
                            Log.i(TAG, "File write took ${writeTime}ms for ${trackData.size} bytes (${track.title})")

                            val totalTime = downloadTime + writeTime
                            Log.i(TAG, "Total time: ${totalTime}ms (download: ${downloadTime}ms / ${(downloadTime.toFloat()/totalTime*100).toInt()}%, write: ${writeTime}ms / ${(writeTime.toFloat()/totalTime*100).toInt()}%)")


                            if (success) {
                                // Save to database
                                dbHelper.insertOrUpdateTrack(
                                    DatabaseHelper.SyncedTrack(
                                        id = track.id,
                                        title = track.title,
                                        artist = track.artist,
                                        album = track.album,
                                        albumArtist = track.albumArtist,
                                        localPath = filePath,
                                        serverPath = track.path,
                                        downloadTimestamp = System.currentTimeMillis(),
                                        fileSize = trackData.size.toLong(),
                                        genre = track.genre ?: "",
                                        lengthMs = track.lengthMs,
                                        trackNumber = track.trackNumber,
                                        discNumber = track.discNumber,
                                        year = track.year,
                                        artworkUrl = track.artworkUrl ?: "",
                                        artworkPath = null
                                    )
                                )

                                tracksDownloaded++
                                Log.i(TAG, "Downloaded track: ${track.title}")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error downloading track ${track.id}", e)
                        }
                    }

                    // Add all tracks to playlist relationship
                    dbHelper.clearPlaylistTracks(playlistId)
                    for (trackId in serverTrackIds) {
                        dbHelper.addTrackToPlaylist(playlistId, trackId)
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

                } catch (e: Exception) {
                    Log.e(TAG, "Error syncing playlist $playlistId", e)
                }
            }

            val duration = System.currentTimeMillis() - startTime

            // Prepare playlist details for history
            val playlistDetails = mutableListOf<Map<String, Any>>()
            for (playlistId in playlistIds) {
                try {
                    val playlist = dbHelper.getPlaylistById(playlistId)
                    if (playlist != null) {
                        val trackCount = dbHelper.getTracksForPlaylist(playlistId).size
                        playlistDetails.add(mapOf(
                            "playlist_id" to playlistId,
                            "playlist_name" to playlist.name,
                            "tracks_in_playlist" to trackCount
                        ))
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting playlist details for history", e)
                }
            }

            // Log sync history
            val syncId = dbHelper.insertSyncHistory(
                DatabaseHelper.SyncHistoryRecord(
                    timestamp = System.currentTimeMillis(),
                    status = if (syncCancelled) "cancelled" else "success",
                    playlistsSynced = playlistIds.size,
                    tracksDownloaded = tracksDownloaded,
                    tracksDeleted = 0,
                    errorMessage = if (syncCancelled) "Cancelled by user" else null,
                    durationMs = duration,
                    triggerType = triggerType
                )
            )

            // Insert playlist details
            for (detail in playlistDetails) {
                dbHelper.insertSyncHistoryPlaylist(
                    DatabaseHelper.SyncHistoryPlaylist(
                        syncId = syncId.toInt(),
                        playlistId = detail["playlist_id"] as Int,
                        playlistName = detail["playlist_name"] as String,
                        tracksInPlaylist = detail["tracks_in_playlist"] as Int
                    )
                )
            }

            // Schedule next sync
            scheduleNextSync()

            Log.i(TAG, "Background sync completed: $tracksDownloaded tracks downloaded in ${duration}ms")
            Result.success()

        } catch (e: CancellationException) {
            Log.i(TAG, "Sync cancelled")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background sync failed", e)
            Result.failure()
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
            val gson = com.google.gson.Gson()
            val schedule = gson.fromJson(syncScheduleJson, SyncSchedule::class.java)

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
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling next sync", e)
        }
    }

    data class SyncSchedule(
        val enabled: Boolean,
        val hour: Int,
        val minute: Int,
        val requiresCharging: Boolean,
        val requiresWifi: Boolean
    )

}