package at.aw.pdfzubild

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Reicht eine per "Öffnen mit" empfangene PDF an die Flutter-Seite weiter.
 *
 * - Kaltstart: Flutter fragt beim Start über `getOpenedFile` den Pfad ab (Pull).
 * - Warmstart (App läuft schon): wir schieben den Pfad aktiv per `openFile` an
 *   Flutter (Push), damit auch dann der Reader aufgeht.
 *
 * Wichtig für E-Mail-Apps (Gmail & Co.): die liefern `content://`-URIs mit
 * kryptischen letzten Pfadsegmenten. Daher wird der echte Dateiname über den
 * ContentResolver ermittelt und der Name vor dem Speichern bereinigt.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "at.aw.pdfzubild/open"
    private var pendingPath: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingPath = extractPdf(intent)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getOpenedFile" -> {
                    result.success(pendingPath)
                    pendingPath = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractPdf(intent) ?: return
        // App läuft schon -> Pfad aktiv an Flutter schieben.
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("openFile", path)
        } else {
            pendingPath = path
        }
    }

    /** Kopiert die per Intent übergebene PDF in den Cache und gibt den Pfad zurück. */
    private fun extractPdf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        return try {
            val display = queryDisplayName(uri)
            val base = sanitize(display)
            val safeName = if (base.endsWith(".pdf", true)) base else "$base.pdf"
            val outFile = File(cacheDir, "geoeffnet_$safeName")
            val copied = contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
            if (copied != null && outFile.exists() && outFile.length() > 0) {
                outFile.absolutePath
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Ermittelt den Anzeigenamen (E-Mail-Apps: über den ContentResolver). */
    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c ->
                        if (c.moveToFirst()) {
                            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) {
                                val n = c.getString(idx)
                                if (!n.isNullOrBlank()) return n
                            }
                        }
                    }
            } catch (e: Exception) {
                // ignorieren -> Fallback unten
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    /** Macht aus einem beliebigen Namen einen sicheren Dateinamen. */
    private fun sanitize(name: String?): String {
        val cleaned = (name ?: "dokument")
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .takeLast(80)
        return cleaned.ifBlank { "dokument" }
    }
}
