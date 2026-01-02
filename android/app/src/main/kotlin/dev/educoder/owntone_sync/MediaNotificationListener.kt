package dev.educoder.owntone_sync

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.util.Log

class MediaNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "MediaNotificationListener"
        private const val DB_NAME = "owntone_sync.db"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val TRACKING_ENABLED_KEY = "flutter.event_tracking_enabled"

        // Playback tracking thresholds
        private const val PLAY_COMPLETION_THRESHOLD = 0.9 // 90% of track must be played
        private const val SKIP_MINIMUM_DURATION_MS = 3000L // 3 seconds minimum before skip counts
    }

    private val activeControllers = mutableMapOf<String, MediaController>()
    private val trackingData = mutableMapOf<String, TrackingData>()

    data class TrackingData(
        val title: String,
        val artist: String,
        val album: String,
        val durationMs: Long,
        var startPositionMs: Long,
        var startTime: Long
    )

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "MediaNotificationListener service created")
    }

    private fun isTrackingEnabled(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(TRACKING_ENABLED_KEY, false)
        Log.d(TAG, "Event tracking enabled: $enabled")
        return enabled
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!isTrackingEnabled()) {
            return
        }

        try {
            val notification = sbn.notification ?: return

            val extras = notification.extras
            val mediaSession = extras.getParcelable<MediaSession.Token>(
                android.app.Notification.EXTRA_MEDIA_SESSION
            ) ?: return

            val controller = MediaController(this, mediaSession)
            val packageName = sbn.packageName

            Log.d(TAG, "Media notification posted from: $packageName")

            // Track this controller
            activeControllers[packageName] = controller

            // Listen for playback state changes
            controller.registerCallback(object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) {
                    state?.let { handlePlaybackState(it, controller, packageName) }
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        activeControllers.remove(sbn.packageName)
        trackingData.remove(sbn.packageName)
    }

    private fun handlePlaybackState(state: PlaybackState, controller: MediaController, packageName: String) {
        if (!isTrackingEnabled()) {
            return
        }

        try {
            val metadata = controller.metadata ?: return

            val title = metadata.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
            val artist = metadata.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            val album = metadata.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM) ?: ""
            val duration = metadata.getLong(android.media.MediaMetadata.METADATA_KEY_DURATION)

            val stateString = when (state.state) {
                PlaybackState.STATE_PLAYING -> "PLAYING"
                PlaybackState.STATE_PAUSED -> "PAUSED"
                PlaybackState.STATE_STOPPED -> "STOPPED"
                PlaybackState.STATE_SKIPPING_TO_NEXT -> "SKIPPING_TO_NEXT"
                PlaybackState.STATE_SKIPPING_TO_PREVIOUS -> "SKIPPING_TO_PREVIOUS"
                else -> "OTHER(${state.state})"
            }
            Log.d(TAG, "State: $stateString | Track: $title | Position: ${state.position}ms / ${duration}ms")

            when (state.state) {
                PlaybackState.STATE_PLAYING -> {
                    val existingData = trackingData[packageName]
                    val isNewTrack = existingData == null ||
                                    existingData.title != title ||
                                    existingData.artist != artist

                    if (isNewTrack) {
                        // A different track was playing before, process it as completed
                        if (existingData != null) {
                            // Track changed naturally - assume it played to completion
                            processTrackEnd(existingData, wasCompleted = true)
                        }

                        // Start tracking new track
                        Log.d(TAG, "Started tracking: $title by $artist")
                        trackingData[packageName] = TrackingData(
                            title = title,
                            artist = artist,
                            album = album,
                            durationMs = duration,
                            startPositionMs = state.position,
                            startTime = System.currentTimeMillis()
                        )
                    }
                }

                PlaybackState.STATE_STOPPED -> {
                    // Only process on STOPPED, not PAUSED
                    val data = trackingData[packageName]
                    if (data != null && data.title == title && data.artist == artist) {
                        // Track stopped at current position (likely not completed)
                        processTrackEnd(data, wasCompleted = false, currentPosition = state.position)
                        trackingData.remove(packageName)
                    }
                }

                PlaybackState.STATE_PAUSED -> {
                    // Don't process paused tracks
                    Log.d(TAG, "Track paused, not processing (user might resume)")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling playback state", e)
        }
    }

    private fun processTrackEnd(data: TrackingData, wasCompleted: Boolean, currentPosition: Long = 0) {
        val playedDuration = System.currentTimeMillis() - data.startTime

        val finalPosition = if (wasCompleted) data.durationMs else currentPosition
        val completionRatio = finalPosition.toDouble() / data.durationMs.toDouble()

        Log.d(TAG, "Processing track end: ${data.title} - ${completionRatio * 100}% complete (${finalPosition}ms / ${data.durationMs}ms), played ${playedDuration}ms, wasCompleted=$wasCompleted")

        when {
            completionRatio >= PLAY_COMPLETION_THRESHOLD -> {
                Log.i(TAG, "Recording PLAY event for: ${data.title}")
                insertEvent("play", data.title, data.artist, data.album, data.durationMs)
            }
            playedDuration >= SKIP_MINIMUM_DURATION_MS -> {
                Log.i(TAG, "Recording SKIP event for: ${data.title}")
                insertEvent("skip", data.title, data.artist, data.album, data.durationMs)
            }
            else -> {
                Log.d(TAG, "Ignoring event - track played for only ${playedDuration}ms")
            }
        }
    }

    private fun insertEvent(
        eventType: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Long
    ) {
        try {
            val trackId = findMatchingTrack(title, artist, album, durationMs.toInt())

            if (trackId != null) {
                Log.d(TAG, "Matched track ID: $trackId, inserting $eventType event")

                val db = openDatabase()
                val values = ContentValues().apply {
                    put("track_id", trackId)
                    put("event_type", eventType)
                    put("timestamp", System.currentTimeMillis() / 1000)
                    put("synced", 0)
                }

                db.insert("pending_events", null, values)
                db.close()

                Log.i(TAG, "Event inserted successfully")
            } else {
                Log.w(TAG, "No matching track found for: $title by $artist")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting event", e)
        }
    }

    private fun findMatchingTrack(
        title: String,
        artist: String,
        album: String,
        durationMs: Int
    ): Int? {
        try {
            val db = openDatabase()

            val cursor = db.query(
                "synced_tracks",
                arrayOf("id", "title", "artist", "album_artist", "length_ms"),
                null,
                null,
                null,
                null,
                null
            )

            var matchedId: Int? = null

            while (cursor.moveToNext()) {
                val id = cursor.getInt(0)
                val trackTitle = cursor.getString(1)
                val trackArtist = cursor.getString(2)
                val trackAlbumArtist = cursor.getString(3)
                val trackDuration = cursor.getInt(4)

                val titleMatch = trackTitle.equals(title, ignoreCase = true)
                val artistMatch = trackArtist.equals(artist, ignoreCase = true) ||
                                trackAlbumArtist.equals(artist, ignoreCase = true)

                val durationDiff = Math.abs(trackDuration - durationMs)
                val durationMatch = durationDiff < 5000

                if (titleMatch && artistMatch && durationMatch) {
                    matchedId = id
                    break
                }
            }

            cursor.close()
            db.close()

            return matchedId
        } catch (e: Exception) {
            Log.e(TAG, "Error finding matching track", e)
            return null
        }
    }

    private fun openDatabase(): SQLiteDatabase {
        val dbPath = getDatabasePath(DB_NAME)
        return SQLiteDatabase.openDatabase(
            dbPath.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE
        )
    }
}