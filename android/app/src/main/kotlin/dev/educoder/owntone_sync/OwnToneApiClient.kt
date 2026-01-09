package dev.educoder.owntone_sync

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import android.util.Log

class OwnToneApiClient(private val baseUrl: String) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()

    // Data classes matching API responses
    data class PlaylistsResponse(
        @SerializedName("items") val items: List<Playlist>,
        @SerializedName("total") val total: Int,
        @SerializedName("offset") val offset: Int,
        @SerializedName("limit") val limit: Int
    )

    data class Playlist(
        @SerializedName("id") val id: Int,
        @SerializedName("name") val name: String,
        @SerializedName("path") val path: String,
        @SerializedName("type") val type: String
    )

    data class TracksResponse(
        @SerializedName("items") val items: List<Track>,
        @SerializedName("total") val total: Int,
        @SerializedName("offset") val offset: Int,
        @SerializedName("limit") val limit: Int
    )

    data class Track(
        @SerializedName("id") val id: Int,
        @SerializedName("title") val title: String,
        @SerializedName("artist") val artist: String,
        @SerializedName("album") val album: String,
        @SerializedName("album_artist") val albumArtist: String,
        @SerializedName("path") val path: String,
        @SerializedName("type") val type: String,
        @SerializedName("genre") val genre: String?,
        @SerializedName("length_ms") val lengthMs: Int,
        @SerializedName("track_number") val trackNumber: Int,
        @SerializedName("disc_number") val discNumber: Int,
        @SerializedName("year") val year: Int,
        @SerializedName("artwork_url") val artworkUrl: String?,
        @SerializedName("album_id") val albumId: String,
        @SerializedName("play_count") val playCount: Int = 0,
        @SerializedName("skip_count") val skipCount: Int = 0,
        @SerializedName("time_played") val timePlayed: String? = null,
        @SerializedName("time_skipped") val timeSkipped: String? = null
    )

    fun getPlaylists(limit: Int = 1000): PlaylistsResponse {
        val request = Request.Builder()
            .url("$baseUrl/api/library/playlists?limit=$limit")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val body = response.body?.string() ?: throw IOException("Empty response")
            return gson.fromJson(body, PlaylistsResponse::class.java)
        }
    }

    fun getPlaylistTracks(playlistId: Int, limit: Int = 10000): TracksResponse {
        val request = Request.Builder()
            .url("$baseUrl/api/library/playlists/$playlistId/tracks?limit=$limit")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val body = response.body?.string() ?: throw IOException("Empty response")
            return gson.fromJson(body, TracksResponse::class.java)
        }
    }

    fun downloadTrack(trackId: Int, onProgress: ((bytesRead: Long, totalBytes: Long) -> Unit)? = null): Pair<ByteArray, String> {
        val url = "$baseUrl/databases/1/items/$trackId.dat?no_register_playback=1"
        Log.d("OwnToneApiClient", "Downloading track $trackId from: $url")

        val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept-Codecs", "mpeg,alac,flac,wav")
        connection.connectTimeout = 10000
        connection.readTimeout = 60000

        try {
            connection.connect()
            Log.d("OwnToneApiClient", "Connected, response code: ${connection.responseCode}")

            val contentType = connection.getHeaderField("Content-Type") ?: "audio/mpeg"
            val contentLength = connection.contentLength.toLong()
            val inputStream = connection.inputStream

            // Read with progress tracking
            val buffer = ByteArray(8192)
            val output = java.io.ByteArrayOutputStream()
            var bytesRead = 0L
            var read: Int
            var lastProgressUpdate = 0L

            while (inputStream.read(buffer).also { read = it } != -1) {
                output.write(buffer, 0, read)
                bytesRead += read

                // Throttle progress callbacks to every 500ms
                val now = System.currentTimeMillis()
                if (now - lastProgressUpdate >= 500) {
                    lastProgressUpdate = now
                    onProgress?.invoke(bytesRead, contentLength)
                }
            }

            // Final progress update at 100%
            onProgress?.invoke(bytesRead, contentLength)

            val bytes = output.toByteArray()

            Log.d("OwnToneApiClient", "Downloaded ${bytes.size} bytes, type: $contentType")
            return Pair(bytes, contentType)
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
            return gson.fromJson(body, Track::class.java)
        }
    }
}