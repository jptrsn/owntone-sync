package dev.educoder.owntone_sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import io.flutter.plugin.common.EventChannel
import java.util.UUID
import androidx.work.CoroutineWorker

object SyncProgressBroadcaster {
    var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private const val NOTIFICATION_ID = 1
    private const val CHANNEL_ID = "sync_channel"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Music Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background music synchronization"
            }

            val notificationManager = context.getSystemService(
                NotificationManager::class.java
            )
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun createForegroundInfo(
        context: Context,
        workerId: UUID,
        currentPlaylist: String,
        currentPlaylistIndex: Int,
        totalPlaylists: Int,
        downloadedTracks: Int,
        totalTracks: Int,
        currentTrackTitle: String? = null,
        downloadProgress: Double? = null
    ): ForegroundInfo {
        // Build notification text
        val notificationText = if (currentTrackTitle != null) {
            "$currentPlaylist - $currentTrackTitle"
        } else {
            currentPlaylist
        }

        val intent = context.packageManager.getLaunchIntentForPackage(
            context.packageName
        )
        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            0,
            intent,
            android.app.PendingIntent.FLAG_IMMUTABLE
        )

        // Cancel intent
        val cancelIntent = WorkManager.getInstance(context)
            .createCancelPendingIntent(workerId)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Syncing Music")
            .setContentText(notificationText)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_delete,
                "Cancel",
                cancelIntent
            )
            .setProgress(
                if (downloadProgress != null) 100 else totalTracks,
                if (downloadProgress != null) (downloadProgress * 100).toInt() else downloadedTracks,
                totalTracks == 0 && downloadProgress == null
            )
            .setSubText("Playlist ${currentPlaylistIndex + 1}/$totalPlaylists • Track $downloadedTracks/$totalTracks")
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    suspend fun updateProgress(
        context: Context,
        worker: CoroutineWorker,
        currentPlaylist: String,
        currentPlaylistIndex: Int,
        totalPlaylists: Int,
        downloadedTracks: Int,
        totalTracks: Int,
        currentTrackTitle: String? = null,
        downloadProgress: Double? = null
    ) {
        // Create and set foreground notification
        val foregroundInfo = createForegroundInfo(
            context,
            worker.id,
            currentPlaylist,
            currentPlaylistIndex,
            totalPlaylists,
            downloadedTracks,
            totalTracks,
            currentTrackTitle,
            downloadProgress
        )
        worker.setForeground(foregroundInfo)

        // Send to Dart on main thread
        val progressData = mapOf(
            "currentPlaylist" to currentPlaylist,
            "currentPlaylistIndex" to currentPlaylistIndex,
            "totalPlaylists" to totalPlaylists,
            "downloadedTracks" to downloadedTracks,
            "totalTracks" to totalTracks,
            "currentTrackTitle" to currentTrackTitle,
            "downloadProgress" to downloadProgress
        )

        mainHandler.post {
            eventSink?.success(progressData)
        }
    }
}