package dev.educoder.owntone_sync

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * JVM unit tests for [detectImageExtension]: JPEG and PNG magic bytes, and
 * the fallback for anything else (including inputs too short to sniff).
 */
class DetectImageExtensionTest {

    @Test
    fun jpegMagicBytesAreDetected() {
        // Minimal JPEG header: FF D8 FF, followed by a SOF marker byte.
        assertEquals("jpg", detectImageExtension(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte())))
    }

    @Test
    fun pngMagicBytesAreDetected() {
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A (8 bytes).
        assertEquals(
            "png",
            detectImageExtension(
                byteArrayOf(
                    0x89.toByte(), 0x50, 0x4E, 0x47,
                    0x0D, 0x0A, 0x1A, 0x0A
                )
            )
        )
    }

    @Test
    fun unknownBytesFallBackToJpg() {
        assertEquals("jpg", detectImageExtension(byteArrayOf(0x00, 0x01, 0x02)))
        assertEquals("jpg", detectImageExtension(ByteArray(0)))
    }

    @Test
    fun inputsTooShortToSniffFallBackToJpg() {
        // Two bytes: too short for the 3-byte JPEG signature.
        assertEquals("jpg", detectImageExtension(byteArrayOf(0xFF.toByte(), 0xD8.toByte())))
        // Four bytes: too short for the 8-byte PNG signature, even though
        // the first four bytes are the PNG magic.
        assertEquals(
            "jpg",
            detectImageExtension(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47))
        )
    }
}
