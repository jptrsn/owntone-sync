package dev.educoder.owntone_sync

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log

class DatabaseHelper(private val context: Context) {

    companion object {
        private const val TAG = "DatabaseHelper"
        private const val DB_NAME = "owntone_sync.db"
    }

    private fun openDatabase(): SQLiteDatabase {
        val dbPath = context.getDatabasePath(DB_NAME)
        return SQLiteDatabase.openDatabase(
            dbPath.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE
        )
    }

    // Playlist operations
    fun insertOrUpdatePlaylist(playlist: SyncedPlaylist) {
        val db = openDatabase()
        val values = ContentValues().apply {
            put("id", playlist.id)
            put("name", playlist.name)
            put("path", playlist.path)
            put("type", playlist.type)
            put("last_synced", playlist.lastSynced)
        }
        db.insertWithOnConflict("synced_playlists", null, values, SQLiteDatabase.CONFLICT_REPLACE)
        db.close()
    }

    fun getAllPlaylists(): List<SyncedPlaylist> {
        val db = openDatabase()
        val playlists = mutableListOf<SyncedPlaylist>()
        val cursor = db.query("synced_playlists", null, null, null, null, null, null)

        while (cursor.moveToNext()) {
            playlists.add(SyncedPlaylist.fromCursor(cursor))
        }

        cursor.close()
        db.close()
        return playlists
    }

    fun deletePlaylist(id: Int) {
        val db = openDatabase()
        db.delete("synced_playlists", "id = ?", arrayOf(id.toString()))
        db.close()
    }

    // Track operations
    fun insertOrUpdateTrack(track: SyncedTrack) {
        val db = openDatabase()
        val values = ContentValues().apply {
            put("id", track.id)
            put("title", track.title)
            put("artist", track.artist)
            put("album", track.album)
            put("album_artist", track.albumArtist)
            put("local_path", track.localPath)
            put("server_path", track.serverPath)
            put("download_timestamp", track.downloadTimestamp)
            put("file_size", track.fileSize)
            put("genre", track.genre)
            put("length_ms", track.lengthMs)
            put("track_number", track.trackNumber)
            put("disc_number", track.discNumber)
            put("year", track.year)
            put("artwork_url", track.artworkUrl)
            put("artwork_path", track.artworkPath)
        }
        db.insertWithOnConflict("synced_tracks", null, values, SQLiteDatabase.CONFLICT_REPLACE)
        db.close()
    }

    fun getTrackById(id: Int): SyncedTrack? {
        val db = openDatabase()
        val cursor = db.query(
            "synced_tracks",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null, null, null
        )

        val track = if (cursor.moveToFirst()) {
            SyncedTrack.fromCursor(cursor)
        } else null

        cursor.close()
        db.close()
        return track
    }

    fun getTracksByIds(ids: List<Int>): Map<Int, SyncedTrack> {
        if (ids.isEmpty()) return emptyMap()

        val db = openDatabase()
        val placeholders = ids.joinToString(",") { "?" }
        val cursor = db.query(
            "synced_tracks",
            null,
            "id IN ($placeholders)",
            ids.map { it.toString() }.toTypedArray(),
            null, null, null
        )

        val tracks = mutableMapOf<Int, SyncedTrack>()
        while (cursor.moveToNext()) {
            val track = SyncedTrack.fromCursor(cursor)
            tracks[track.id] = track
        }

        cursor.close()
        db.close()
        return tracks
    }

    fun deleteTrack(id: Int) {
        val db = openDatabase()
        db.delete("synced_tracks", "id = ?", arrayOf(id.toString()))
        db.close()
    }

    // Playlist-Track relationship
    fun addTrackToPlaylist(playlistId: Int, trackId: Int) {
        val db = openDatabase()
        val values = ContentValues().apply {
            put("playlist_id", playlistId)
            put("track_id", trackId)
        }
        db.insertWithOnConflict("playlist_tracks", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        db.close()
    }

    fun clearPlaylistTracks(playlistId: Int) {
        val db = openDatabase()
        db.delete("playlist_tracks", "playlist_id = ?", arrayOf(playlistId.toString()))
        db.close()
    }

    // Sync history
    fun insertSyncHistory(record: SyncHistoryRecord): Long {
        val db = openDatabase()
        val values = ContentValues().apply {
            put("timestamp", record.timestamp)
            put("status", record.status)
            put("playlists_synced", record.playlistsSynced)
            put("tracks_downloaded", record.tracksDownloaded)
            put("tracks_deleted", record.tracksDeleted)
            put("error_message", record.errorMessage)
            put("duration_ms", record.durationMs)
            put("trigger_type", record.triggerType)
        }
        val id = db.insert("sync_history", null, values)
        db.close()
        return id
    }

    fun insertSyncHistoryPlaylist(playlist: SyncHistoryPlaylist) {
        val db = openDatabase()
        val values = ContentValues().apply {
            put("sync_id", playlist.syncId)
            put("playlist_id", playlist.playlistId)
            put("playlist_name", playlist.playlistName)
            put("tracks_in_playlist", playlist.tracksInPlaylist)
        }
        db.insert("sync_history_playlists", null, values)
        db.close()
    }

    fun getTracksForPlaylist(playlistId: Int): List<SyncedTrack> {
        val db = openDatabase()
        val cursor = db.rawQuery(
            """
            SELECT st.* FROM synced_tracks st
            INNER JOIN playlist_tracks pt ON st.id = pt.track_id
            WHERE pt.playlist_id = ?
            """,
            arrayOf(playlistId.toString())
        )

        val tracks = mutableListOf<SyncedTrack>()
        while (cursor.moveToNext()) {
            tracks.add(SyncedTrack.fromCursor(cursor))
        }

        cursor.close()
        db.close()
        return tracks
    }

    fun getPlaylistById(id: Int): SyncedPlaylist? {
        val db = openDatabase()
        val cursor = db.query(
            "synced_playlists",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null, null, null
        )

        val playlist = if (cursor.moveToFirst()) {
            SyncedPlaylist.fromCursor(cursor)
        } else null

        cursor.close()
        db.close()
        return playlist
    }

    // Data classes
    data class SyncedPlaylist(
        val id: Int,
        val name: String,
        val path: String,
        val type: String,
        val lastSynced: Long
    ) {
        companion object {
            fun fromCursor(cursor: Cursor) = SyncedPlaylist(
                id = cursor.getInt(cursor.getColumnIndexOrThrow("id")),
                name = cursor.getString(cursor.getColumnIndexOrThrow("name")),
                path = cursor.getString(cursor.getColumnIndexOrThrow("path")),
                type = cursor.getString(cursor.getColumnIndexOrThrow("type")),
                lastSynced = cursor.getLong(cursor.getColumnIndexOrThrow("last_synced"))
            )
        }
    }

    data class SyncedTrack(
        val id: Int,
        val title: String,
        val artist: String,
        val album: String,
        val albumArtist: String,
        val localPath: String,
        val serverPath: String,
        val downloadTimestamp: Long,
        val fileSize: Long,
        val genre: String,
        val lengthMs: Int,
        val trackNumber: Int,
        val discNumber: Int,
        val year: Int,
        val artworkUrl: String,
        val artworkPath: String?
    ) {
        companion object {
            fun fromCursor(cursor: Cursor) = SyncedTrack(
                id = cursor.getInt(cursor.getColumnIndexOrThrow("id")),
                title = cursor.getString(cursor.getColumnIndexOrThrow("title")),
                artist = cursor.getString(cursor.getColumnIndexOrThrow("artist")),
                album = cursor.getString(cursor.getColumnIndexOrThrow("album")),
                albumArtist = cursor.getString(cursor.getColumnIndexOrThrow("album_artist")),
                localPath = cursor.getString(cursor.getColumnIndexOrThrow("local_path")),
                serverPath = cursor.getString(cursor.getColumnIndexOrThrow("server_path")),
                downloadTimestamp = cursor.getLong(cursor.getColumnIndexOrThrow("download_timestamp")),
                fileSize = cursor.getLong(cursor.getColumnIndexOrThrow("file_size")),
                genre = cursor.getString(cursor.getColumnIndexOrThrow("genre")) ?: "",
                lengthMs = cursor.getInt(cursor.getColumnIndexOrThrow("length_ms")),
                trackNumber = cursor.getInt(cursor.getColumnIndexOrThrow("track_number")),
                discNumber = cursor.getInt(cursor.getColumnIndexOrThrow("disc_number")),
                year = cursor.getInt(cursor.getColumnIndexOrThrow("year")),
                artworkUrl = cursor.getString(cursor.getColumnIndexOrThrow("artwork_url")) ?: "",
                artworkPath = cursor.getString(cursor.getColumnIndexOrThrow("artwork_path"))
            )
        }
    }

    data class SyncHistoryRecord(
        val timestamp: Long,
        val status: String,
        val playlistsSynced: Int,
        val tracksDownloaded: Int,
        val tracksDeleted: Int,
        val errorMessage: String?,
        val durationMs: Long,
        val triggerType: String
    )

    data class SyncHistoryPlaylist(
        val syncId: Int,
        val playlistId: Int,
        val playlistName: String,
        val tracksInPlaylist: Int
    )

}