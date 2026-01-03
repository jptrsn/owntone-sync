package dev.educoder.owntone_sync

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class BackgroundSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "BackgroundSyncWorker"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "sync_channel"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            // Create notification channel
            createNotificationChannel()

            // Show initial notification
            setForeground(createForegroundInfo("Starting sync...", 0, 0, 0, 0))

            Log.i(TAG, "Starting background sync")

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
                    setForeground(createForegroundInfo(
                        playlist.name,
                        playlistIndex + 1,
                        playlistIds.size,
                        tracksDownloaded,
                        totalTracks
                    ))

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
                        localTrack == null || !fileOps.fileExists(localTrack.localPath)
                    }

                    Log.i(TAG, "Need to download ${tracksToDownload.size} tracks")

                    // Download tracks
                    for (track in tracksToDownload) {
                        try {
                            // Update notification for current track
                            setForeground(createForegroundInfo(
                                "${playlist.name} - ${track.title}",
                                playlistIndex + 1,
                                playlistIds.size,
                                tracksDownloaded,
                                totalTracks
                            ))

                            // Download track data and get content type
                            val (trackData, contentType) = apiClient.downloadTrack(track.id)
                            val extension = fileOps.getExtensionFromContentType(contentType)

                            // Generate file path
                            val filename = fileOps.generateTrackFilename(track, extension)
                            val filePath = "tracks/$filename"

                            // Write to file
                            val success = fileOps.writeFile(filePath, trackData)

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

            // Log sync history
            dbHelper.insertSyncHistory(
                DatabaseHelper.SyncHistoryRecord(
                    timestamp = System.currentTimeMillis(),
                    status = "success",
                    playlistsSynced = playlistIds.size,
                    tracksDownloaded = tracksDownloaded,
                    tracksDeleted = 0,
                    errorMessage = null,
                    durationMs = duration,
                    triggerType = "scheduled"
                )
            )

            Log.i(TAG, "Background sync completed: $tracksDownloaded tracks downloaded in ${duration}ms")
            Result.success()

        } catch (e: Exception) {
            Log.e(TAG, "Background sync failed", e)
            Result.failure()
        }
    }

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "Music Sync",
                android.app.NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background music synchronization"
            }

            val notificationManager = applicationContext.getSystemService(
                android.app.NotificationManager::class.java
            )
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createForegroundInfo(
        currentTrack: String,
        currentPlaylist: Int,
        totalPlaylists: Int,
        downloadedTracks: Int,
        totalTracks: Int
    ): ForegroundInfo {
        val intent = applicationContext.packageManager.getLaunchIntentForPackage(
            applicationContext.packageName
        )
        val pendingIntent = android.app.PendingIntent.getActivity(
            applicationContext,
            0,
            intent,
            android.app.PendingIntent.FLAG_IMMUTABLE
        )

        // Cancel intent
        val cancelIntent = WorkManager.getInstance(applicationContext)
            .createCancelPendingIntent(id)

        val notification = androidx.core.app.NotificationCompat.Builder(
            applicationContext,
            CHANNEL_ID
        )
            .setContentTitle("Syncing Music")
            .setContentText(currentTrack)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_delete,
                "Cancel",
                cancelIntent
            )
            .setProgress(
                totalTracks,
                downloadedTracks,
                totalTracks == 0
            )
            .setSubText("Playlist $currentPlaylist/$totalPlaylists • Track $downloadedTracks/$totalTracks")
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
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
}