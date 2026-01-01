package dev.educoder.owntone_sync

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.PlaybackState
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.FlutterEngineCache
import android.content.Context

class MediaNotificationListener : NotificationListenerService() {

    companion object {
        private const val CHANNEL = "dev.educoder.owntone_sync/events"
    }

    private var methodChannel: MethodChannel? = null
    private val activeControllers = mutableMapOf<String, MediaController>()

    override fun onCreate() {
        super.onCreate()
        setupFlutterCommunication()
    }

    private fun setupFlutterCommunication() {
        val flutterEngine = FlutterEngineCache.getInstance().get("event_tracker")
        if (flutterEngine != null) {
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return

        val extras = notification.extras
        val mediaSession = extras.getParcelable<MediaSession.Token>(
            android.app.Notification.EXTRA_MEDIA_SESSION
        ) ?: return

        val controller = MediaController(this, mediaSession)
        val packageName = sbn.packageName

        activeControllers[packageName] = controller

        controller.registerCallback(object : MediaController.Callback() {
            override fun onPlaybackStateChanged(state: PlaybackState?) {
                state?.let { handlePlaybackState(it, controller) }
            }
        })
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        activeControllers.remove(sbn.packageName)
    }

    private fun handlePlaybackState(state: PlaybackState, controller: MediaController) {
        val metadata = controller.metadata ?: return

        val title = metadata.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
        val artist = metadata.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        val album = metadata.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val duration = metadata.getLong(android.media.MediaMetadata.METADATA_KEY_DURATION)

        when (state.state) {
            PlaybackState.STATE_PLAYING -> {
                sendEvent("play", title, artist, album, duration)
            }
            PlaybackState.STATE_SKIPPING_TO_NEXT,
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS -> {
                sendEvent("skip", title, artist, album, duration)
            }
        }
    }

    private fun sendEvent(
        eventType: String,
        title: String,
        artist: String,
        album: String,
        duration: Long
    ) {
        val data = mapOf(
            "eventType" to eventType,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "duration" to duration
        )

        methodChannel?.invokeMethod("onPlaybackEvent", data)
    }
}