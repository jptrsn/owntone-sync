package dev.educoder.owntone_sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.StandardCharsets.ISO_8859_1

/**
 * JVM unit tests for the [ServerDiscoveryStreamHandler] TXT-decode helpers
 * (frozen spec, issue 13: "TXT extraction ... decode ISO-8859-1"; AGENTS
 * gate "TXT-decode tests"). Pure functions, no Robolectric — the
 * [DetectImageExtensionTest] precedent.
 */
class ServerDiscoveryTxtTest {

    /**
     * K1 — TXT records decode as ISO-8859-1 and expose mtd-version. The
     * 0xE9 → 'é' leg is the mojibake guard: a UTF-8 decode of a DNS-SD TXT
     * byte (RFC 6762 §6 defines Latin-1) would land U+FFFD where the user
     * expects their machine name.
     */
    @Test
    fun txtRecordsDecodeAsIso88591AndExposeMtdVersion() {
        val txt = decodeTxtRecords(
            mapOf(
                "mtd-version" to "29.3".toByteArray(ISO_8859_1),
                "Machine Name" to "My Music é".toByteArray(ISO_8859_1),
            )
        )
        assertEquals("29.3", txt["mtd-version"])
        assertTrue(txt.containsKey("mtd-version"))
        assertEquals("My Music é", txt["Machine Name"])
        // The exact byte that a UTF-8 decode would mangle into U+FFFD.
        assertTrue(txt["Machine Name"]!!.contains('é'))
    }

    /**
     * K2 — null/empty records and malformed entries are tolerated (the
     * minSdk-27 fallback shape): null → empty map, an entry without `=`
     * survives as key → "" (the implemented contract), and parseTxtEntries
     * splits on the FIRST `=` only, so a value containing `=` survives
     * intact.
     */
    @Test
    fun nullRecordsDecodeToEmptyMap() {
        assertEquals(emptyMap<String, String>(), decodeTxtRecords(null))
        assertEquals(emptyMap<String, String>(), decodeTxtRecords(emptyMap()))
    }

    @Test
    fun entryWithoutEqualsSurvivesAsKeyToEmptyValue() {
        val parsed = parseTxtEntries(listOf("flag"))
        assertEquals(mapOf("flag" to ""), parsed)
    }

    @Test
    fun parseSplitsOnTheFirstEqualsOnly() {
        // A value containing '=' must survive whole: key "Password", value
        // "a=b" — a second split would truncate the value to "a".
        val parsed = parseTxtEntries(listOf("Password=a=b", "mtd-version=29.3"))
        assertEquals("a=b", parsed["Password"])
        assertEquals("29.3", parsed["mtd-version"])
    }

    @Test
    fun nullAndEmptyEntryListsAreTolerated() {
        assertEquals(emptyMap<String, String>(), parseTxtEntries(null))
        assertEquals(emptyMap<String, String>(), parseTxtEntries(emptyList()))
        // An empty-string entry is dropped (nothing to key on), not a throw.
        assertEquals(emptyMap<String, String>(), parseTxtEntries(listOf("")))
    }
}
