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
        @SerializedName("album_id") val albumId: String
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
}