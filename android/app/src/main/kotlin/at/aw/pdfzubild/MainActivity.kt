package at.aw.pdfzubild

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Reicht eine per "Öffnen mit" empfangene PDF an die Flutter-Seite weiter.
 * Flutter fragt beim Start über den MethodChannel den Pfad der geöffneten Datei ab.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "at.aw.pdfzubild/open"
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingPath = extractPdf(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
        extractPdf(intent)?.let { pendingPath = it }
    }

    /** Kopiert die per Intent übergebene PDF in den Cache und gibt den Pfad zurück. */
    private fun extractPdf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        return try {
            val name = (uri.lastPathSegment ?: "dokument").substringAfterLast('/')
            val safeName = if (name.endsWith(".pdf", true)) name else "$name.pdf"
            val outFile = File(cacheDir, "geoeffnet_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
            if (outFile.exists() && outFile.length() > 0) outFile.absolutePath else null
        } catch (e: Exception) {
            null
        }
    }
}
