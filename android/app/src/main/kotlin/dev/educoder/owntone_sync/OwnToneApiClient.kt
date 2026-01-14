package dev.educoder.owntone_sync

import com.squareup.moshi.Moshi
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import android.util.Log

class OwnToneApiClient(
        private val baseUrl: String,
        private val fileOps: FileOperations
    ) {

    data class DownloadResult(
        val contentType: String,
        val bytesWritten: Long,
        val filePath: String
    )

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val moshi = Moshi.Builder().build()
    private val playlistsAdapter = moshi.adapter(PlaylistsResponse::class.java)
    private val tracksAdapter = moshi.adapter(TracksResponse::class.java)
    private val trackAdapter = moshi.adapter(Track::class.java)

    // Data classes matching API responses
    @JsonClass(generateAdapter = true)
    data class PlaylistsResponse(
        val items: List<Playlist>,
        val total: Int,
        val offset: Int,
        val limit: Int
    )

    @JsonClass(generateAdapter = true)
    data class Playlist(
        val id: Int,
        val name: String,
        val path: String,
        val type: String
    )

    @JsonClass(generateAdapter = true)
    data class TracksResponse(
        val items: List<Track>,
        val total: Int,
        val offset: Int,
        val limit: Int
    )

    @JsonClass(generateAdapter = true)
    data class Track(
        val id: Int,
        val title: String,
        val artist: String,
        val album: String,
        @Json(name = "album_artist") val albumArtist: String,
        val path: String,
        val type: String,
        val genre: String?,
        @Json(name = "length_ms") val lengthMs: Int,
        @Json(name = "track_number") val trackNumber: Int,
        @Json(name = "disc_number") val discNumber: Int,
        val year: Int,
        @Json(name = "artwork_url") val artworkUrl: String?,
        @Json(name = "album_id") val albumId: String,
        @Json(name = "play_count") val playCount: Int = 0,
        @Json(name = "skip_count") val skipCount: Int = 0,
        @Json(name = "time_played") val timePlayed: String? = null,
        @Json(name = "time_skipped") val timeSkipped: String? = null
    )

    fun getPlaylists(limit: Int = 1000): PlaylistsResponse {
        val request = Request.Builder()
            .url("$baseUrl/api/library/playlists?limit=$limit")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val body = response.body?.string() ?: throw IOException("Empty response")
            return playlistsAdapter.fromJson(body)
                ?: throw IOException("Failed to parse playlists response")
        }
    }

    fun getPlaylistTracks(playlistId: Int, limit: Int = 10000): TracksResponse {
        val request = Request.Builder()
            .url("$baseUrl/api/library/playlists/$playlistId/tracks?limit=$limit")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val body = response.body?.string() ?: throw IOException("Empty response")
            return tracksAdapter.fromJson(body)
                ?: throw IOException("Failed to parse tracks response")
        }
    }

    fun downloadTrack(
        track: Track,
        onProgress: (bytesRead: Long, totalBytes: Long) -> Unit
    ): DownloadResult {
        val url = "$baseUrl/databases/1/items/${track.id}.dat?no_register_playback=1"
        Log.d("OwnToneApiClient", "Downloading track ${track.id} from: $url")

        val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept-Codecs", "mpeg,alac,flac,wav")
        connection.connectTimeout = 10000
        connection.readTimeout = 60000

        try {
            connection.connect()
            val responseCode = connection.responseCode

            if (responseCode != 200) {
                throw IOException("GET request failed with code $responseCode for track ${track.id}")
            }

            Log.d("OwnToneApiClient", "GET request successful, starting stream to storage")

            // Get content type and length from GET response
        val contentType = connection.getHeaderField("Content-Type") ?: "audio/mpeg"
        val contentLength = connection.contentLengthLong

        if (contentLength <= 0) {
            throw IOException("Invalid Content-Length from GET request: $contentLength")
        }

        Log.d("OwnToneApiClient", "GET request successful: type=$contentType, size=$contentLength bytes")

        // Generate filename from content type
        val extension = fileOps.getExtensionFromContentType(contentType)
        val filename = fileOps.generateTrackFilename(track, extension)
        val filePath = "tracks/$filename"

        // Stream directly to storage
        val inputStream = connection.inputStream
        val bytesWritten = fileOps.writeFileStreaming(
            filePath,
            inputStream,
            contentType,
            contentLength,
            onProgress
        )

        Log.d("OwnToneApiClient", "Download completed: $bytesWritten bytes written")

        return DownloadResult(
            contentType = contentType,
            bytesWritten = bytesWritten,
            filePath = filePath
        )

        } finally {
            connection.disconnect()
        }
    }

    fun updateTrackStats(
        trackId: Int,
        additionalPlayCount: Int = 0,
        additionalSkipCount: Int = 0,
        mostRecentTimePlayed: Long? = null,
        mostRecentTimeSkipped: Long? = null
    ) {
        // First, fetch current track stats
        val currentTrack = getTrack(trackId)

        // Calculate new totals
        val newPlayCount = currentTrack.playCount + additionalPlayCount
        val newSkipCount = currentTrack.skipCount + additionalSkipCount

        // Determine timestamps to use (most recent wins)
        val currentTimePlayed = currentTrack.timePlayed?.let {
            // Parse ISO timestamp to epoch seconds
            try {
                val instant = java.time.Instant.parse(it)
                instant.epochSecond
            } catch (e: Exception) {
                null
            }
        }

        val currentTimeSkipped = currentTrack.timeSkipped?.let {
            try {
                val instant = java.time.Instant.parse(it)
                instant.epochSecond
            } catch (e: Exception) {
                null
            }
        }

        val finalTimePlayed = when {
            mostRecentTimePlayed == null -> currentTimePlayed
            currentTimePlayed == null -> mostRecentTimePlayed
            mostRecentTimePlayed > currentTimePlayed -> mostRecentTimePlayed
            else -> currentTimePlayed
        }

        val finalTimeSkipped = when {
            mostRecentTimeSkipped == null -> currentTimeSkipped
            currentTimeSkipped == null -> mostRecentTimeSkipped
            mostRecentTimeSkipped > currentTimeSkipped -> mostRecentTimeSkipped
            else -> currentTimeSkipped
        }

        // Build query parameters
        val url = StringBuilder("$baseUrl/api/library/tracks/$trackId?")
        val params = mutableListOf<String>()

        params.add("play_count=$newPlayCount")
        params.add("skip_count=$newSkipCount")
        if (finalTimePlayed != null) params.add("time_played=$finalTimePlayed")
        if (finalTimeSkipped != null) params.add("time_skipped=$finalTimeSkipped")

        url.append(params.joinToString("&"))

        val request = Request.Builder()
            .url(url.toString())
            .put(okhttp3.RequestBody.create(null, ByteArray(0)))
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Failed to update track stats: ${response.code} ${response.message}")
            }
        }
    }

    fun getTrack(trackId: Int): Track {
        val request = Request.Builder()
            .url("$baseUrl/api/library/tracks/$trackId")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val body = response.body?.string() ?: throw IOException("Empty response")
            return trackAdapter.fromJson(body)
                ?: throw IOException("Failed to parse track response")
        }
    }
}