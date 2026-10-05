package dev.educoder.owntone_sync

import com.squareup.moshi.Moshi
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
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
    private val bulkTrackUpdateAdapter = moshi.adapter(BulkTrackUpdate::class.java)

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
        @Json(name = "rating") val rating: Int = 0,
        @Json(name = "play_count") val playCount: Int = 0,
        @Json(name = "skip_count") val skipCount: Int = 0,
        @Json(name = "time_played") val timePlayed: String? = null,
        @Json(name = "time_skipped") val timeSkipped: String? = null
    )

    // Body for the bulk track update. Rating is absolute (0-100), not a
    // delta, so there is no read-modify-write here (unlike updateTrackStats).
    @JsonClass(generateAdapter = true)
    data class BulkTrackUpdate(
        val tracks: List<BulkTrackUpdateItem>
    )

    @JsonClass(generateAdapter = true)
    data class BulkTrackUpdateItem(
        val id: Int,
        val rating: Int
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
        onProgress: (bytesRead: Long, totalBytes: Long) -> Unit,
        isCancelled: () -> Boolean
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
            onProgress,
            isCancelled
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

    /**
     * Fetches a track's artwork from the server. [artworkUrl] is the
     * relative artwork_url from the track object (e.g. "/artwork/item/874");
     * the baseUrl is prepended — the value is never an absolute URL.
     *
     * Returns null when the track has NO artwork. The server signals that
     * with HTTP 204 No Content and a zero-length body (not 404); a 200 with
     * an empty body is treated the same. Treating 204 as success and
     * writing the empty body would create a zero-byte file — the exact
     * failure the old isSuccessful() check produced.
     *
     * Throws IOException on transport/HTTP failure so the caller can leave
     * the track unresolved and retry on the next sync (a network error is
     * NOT evidence of absence).
     */
    fun fetchTrackArtwork(artworkUrl: String): ByteArray? {
        val url = when {
            artworkUrl.startsWith("http://") || artworkUrl.startsWith("https://") -> artworkUrl
            artworkUrl.startsWith("/") -> "$baseUrl$artworkUrl"
            else -> "$baseUrl/$artworkUrl"
        }
        val request = Request.Builder().url(url).build()
        client.newCall(request).execute().use { response ->
            val bytes = response.body?.bytes() ?: ByteArray(0)
            return when {
                response.code == 204 || bytes.isEmpty() -> null
                response.isSuccessful -> bytes
                else -> throw IOException("Artwork fetch failed: ${response.code} $url")
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

    /**
     * Sets a single track's rating (0-100). Query-parameter shape with a
     * zero-byte body, same convention as updateTrackStats.
     */
    fun updateTrackRating(trackId: Int, rating: Int) {
        val request = Request.Builder()
            .url("$baseUrl/api/library/tracks/$trackId?rating=$rating")
            .put(ByteArray(0).toRequestBody())
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Failed to set rating for track $trackId: ${response.code} ${response.message}")
            }
        }
    }

    /**
     * Sets the ratings of several tracks in one request. The API docs list
     * 204 No Content as the success code; the server at 192.168.1.13
     * returns 200, so any 2xx is accepted. Throws on failure so the caller
     * can fall back to per-track PUTs.
     */
    fun updateTrackRatings(ratings: Map<Int, Int>) {
        if (ratings.isEmpty()) return
        val body = BulkTrackUpdate(ratings.map { (id, rating) -> BulkTrackUpdateItem(id, rating) })
        val request = Request.Builder()
            .url("$baseUrl/api/library/tracks")
            .put(bulkTrackUpdateAdapter.toJson(body).toRequestBody("application/json".toMediaType()))
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Failed to bulk-update track ratings: ${response.code} ${response.message}")
            }
        }
    }
}