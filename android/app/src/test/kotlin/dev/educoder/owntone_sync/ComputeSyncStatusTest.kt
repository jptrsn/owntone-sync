package dev.educoder.owntone_sync

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * JVM unit tests for the pure functions the sync worker delegates to.
 * Plain JUnit — no Robolectric, no instrumentation.
 */
class ComputeSyncStatusTest {

    // cancelled -> "cancelled"
    @Test
    fun cancelledRunReportsCancelledRegardlessOfOutcomes() {
        assertEquals("cancelled", computeSyncStatus(3, 3, cancelled = true))
        assertEquals("cancelled", computeSyncStatus(3, 1, cancelled = true))
        assertEquals("cancelled", computeSyncStatus(0, 0, cancelled = true))
    }

    // every playlist failed -> "failed"
    @Test
    fun everyPlaylistFailedReportsFailed() {
        assertEquals("failed", computeSyncStatus(1, 1, cancelled = false))
        assertEquals("failed", computeSyncStatus(5, 5, cancelled = false))
    }

    // some playlists failed -> "partial"
    @Test
    fun somePlaylistsFailedReportsPartial() {
        assertEquals("partial", computeSyncStatus(5, 1, cancelled = false))
        assertEquals("partial", computeSyncStatus(5, 4, cancelled = false))
        assertEquals("partial", computeSyncStatus(2, 1, cancelled = false))
    }

    // no playlist failures -> "success"
    @Test
    fun noFailuresReportsSuccess() {
        assertEquals("success", computeSyncStatus(5, 0, cancelled = false))
        assertEquals("success", computeSyncStatus(1, 0, cancelled = false))
    }

    // zero-playlist guard: an empty run must not report "failed"
    @Test
    fun emptyRunIsNotAFailure() {
        assertEquals("success", computeSyncStatus(0, 0, cancelled = false))
    }
}
