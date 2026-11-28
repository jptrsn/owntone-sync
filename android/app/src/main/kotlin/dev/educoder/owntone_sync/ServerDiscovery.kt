package dev.educoder.owntone_sync

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.net.Inet4Address
import java.nio.charset.StandardCharsets.ISO_8859_1

private const val TAG = "ServerDiscovery"

/**
 * Decodes NsdServiceInfo TXT records (the API 30+ `attributes` shape,
 * `Map<String, ByteArray>`) into plain strings using ISO-8859-1 — the
 * encoding DNS-SD TXT strings are defined in (RFC 6762 §6). A UTF-8 decode
 * would mojibake every non-ASCII value (0xE9 arriving as U+FFFD), so the
 * `Machine Name` a user recognises could render wrong. Null-safe: a record
 * set the platform did not deliver yields an empty map, never a throw.
 *
 * Top-level pure function (no Context, no NsdManager) so the JVM unit
 * tests can reach it — the pattern of [detectImageExtension].
 */
fun decodeTxtRecords(txtRecords: Map<String, ByteArray>?): Map<String, String> {
    if (txtRecords == null) return emptyMap()
    return txtRecords.mapValues { String(it.value, ISO_8859_1) }
}

/**
 * Parses raw `key=value` TXT entries into a map, splitting on the FIRST
 * `=` only (a value may itself contain `=`). An entry without any `=`
 * survives as key → "" rather than being dropped or throwing (tolerant of
 * malformed announcers, per the frozen spec's "tolerant of entries without
 * `=`, null-safe"). Top-level pure function for the JVM unit tests.
 */
fun parseTxtEntries(entries: Iterable<String>?): Map<String, String> {
    if (entries == null) return emptyMap()
    val out = LinkedHashMap<String, String>()
    for (entry in entries) {
        val idx = entry.indexOf('=')
        if (idx < 0) {
            if (entry.isNotEmpty()) out[entry] = ""
        } else {
            out[entry.substring(0, idx)] = entry.substring(idx + 1)
        }
    }
    return out
}

/**
 * EventChannel stream handler for `dev.educoder.owntone_sync/discovery`
 * (issue 13, maintainer spec comment 7172745528): a DNS-SD **browse** of
 * BOTH `_http._tcp` and `_daap._tcp` (OwnTone registers no dedicated
 * service type; `--mdns-no-web` / `--mdns-no-daap` servers stay reachable
 * through the other type). Each resolved service is forwarded verbatim as
 * one Map over the sink:
 *
 *   {serviceType, instanceName, host, ipv4, port, txt: {key: value}}
 *
 * No filtering happens here: Kotlin decodes and forwards every resolved
 * service; the `mtd-version` filter, the (host, port) dedupe and the
 * candidate-URL build live in the one pure-Dart helper
 * (lib/data/services/server_discovery_service.dart), so the filter is
 * unit-testable without the platform. Browse only — the app never
 * registers a service, and NsdManager takes its own multicast lock, so no
 * new permission is needed (INTERNET is already held).
 *
 * `onListen` = startBrowse, `onCancel` = stopBrowse (the subscription's
 * lifecycle is the browse's lifecycle — the PROGRESS_CHANNEL pattern).
 */
class ServerDiscoveryStreamHandler(context: Context) : EventChannel.StreamHandler {

    private val nsdManager =
        context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager

    // Both types OwnTone advertises on (measured on the user's LAN
    // 2026-11-25: "My Music on hp-server" on both, at :3689).
    private val serviceTypes = listOf("_http._tcp", "_daap._tcp")

    private var eventSink: EventChannel.EventSink? = null
    private val discoveryListeners = mutableListOf<NsdManager.DiscoveryListener>()

    // NsdManager delivers discovery/resolve callbacks on its own
    // HandlerThread (device-observed on the night AVD: FlutterJNI
    // ensureRunningOnMainThread threw out of every EventSink.success,
    // silently dropping resolved services). Sink emissions must therefore
    // be marshalled to the main thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        // Idempotent re-listen: release any previous browse before the new
        // one, so a dangling subscription can never leave two discover
        // calls running on the same types.
        stopBrowse()
        eventSink = events
        for (type in serviceTypes) {
            startBrowse(type)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopBrowse()
    }

    private fun startBrowse(serviceType: String) {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(type: String, errorCode: Int) {
                Log.w(TAG, "NSD start failed for $type: $errorCode")
            }

            override fun onStopDiscoveryFailed(type: String, errorCode: Int) {
                Log.w(TAG, "NSD stop failed for $type: $errorCode")
            }

            override fun onDiscoveryStarted(type: String) {
                Log.d(TAG, "NSD browsing $type")
            }

            override fun onDiscoveryStopped(type: String) {
                Log.d(TAG, "NSD stopped $type")
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                // The single-argument listener (android-31..36) carries
                // the type on the info itself; fall back to the browse
                // type the platform echoes.
                resolveService(serviceInfo.serviceType ?: serviceType, serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                // The Dart side dedupes and re-probes per scan; a lost
                // announcement between scans needs no event here.
            }
        }
        discoveryListeners.add(listener)
        try {
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            Log.w(TAG, "discoverServices($serviceType) failed", e)
        }
    }

    private fun resolveService(serviceType: String, info: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.d(TAG, "NSD resolve failed for ${serviceInfo.serviceName}: $errorCode")
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                mainHandler.post {
                    val sink = eventSink ?: return@post // browse cancelled meanwhile
                    try {
                        sink.success(buildEventMap(serviceType, serviceInfo))
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to forward ${serviceInfo.serviceName}", e)
                    }
                }
            }
        }
        try {
            nsdManager.resolveService(info, resolveListener)
        } catch (e: Exception) {
            Log.w(TAG, "resolveService(${info.serviceName}) failed", e)
        }
    }

    private fun buildEventMap(serviceType: String, info: NsdServiceInfo): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val host: String? = info.host?.hostAddress
        // API 33+: getHostAddresses() is the non-deprecated source and
        // getHost() may return null; below 33 the deprecated host is the
        // only address source. Both are recorded so the Dart helper can
        // prefer the resolved IPv4 literal (maintainer rule) and fall back
        // to the host name when the IPv4 is absent.
        val ipv4: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            info.hostAddresses?.firstOrNull { it is Inet4Address }?.hostAddress
        } else {
            null
        }
        return mapOf(
            "serviceType" to serviceType,
            "instanceName" to info.serviceName,
            "host" to host,
            "ipv4" to ipv4,
            "port" to info.port,
            // `attributes` is the API 30+ TXT surface (Map<String,
            // byte[]>); below 30 the platform exposes no TXT at all, so
            // the map is empty and the Dart-side mtd-version filter keeps
            // such a candidate out — manual entry remains the documented
            // fallback there.
            "txt" to txtRecords(info)
        )
    }

    private fun txtRecords(info: NsdServiceInfo): Map<String, String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            decodeTxtRecords(info.attributes)
        } else {
            emptyMap()
        }
    }

    private fun stopBrowse() {
        for (listener in discoveryListeners) {
            try {
                nsdManager.stopServiceDiscovery(listener)
            } catch (e: IllegalArgumentException) {
                // Already stopped (the platform never accepted or already
                // released this listener) — the release is best-effort and
                // idempotent by contract.
            }
        }
        discoveryListeners.clear()
        eventSink = null
    }
}
