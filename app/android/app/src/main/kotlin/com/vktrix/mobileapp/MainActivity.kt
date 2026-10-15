package com.vktrix.mobileapp

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPdfBytes: ByteArray? = null
    private var pendingPdfResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // In-app updates: Dart downloads the APK into cache/updates, this side hands it
        // to the system installer through a FileProvider (no browser involved).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "updateDir" -> result.success(updatesDir().absolutePath)
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.error("bad_args", "APK path missing", null)
                        else result.success(installApk(File(path)))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("updater_failed", e.message ?: e.javaClass.simpleName, null)
            }
        }

        // PDF receipts are passed as bytes, written only inside this app's cache,
        // and shared through a read-only content URI. WhatsApp then lets the user
        // choose the recipient and press Send; the app never sends automatically.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BILLING_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "savePdf" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = safePdfName(call.argument<String>("fileName"))
                        if (bytes == null) result.error("bad_args", "PDF bytes missing", null)
                        else startSavePdf(bytes, name, result)
                    }
                    "sharePdf" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = safePdfName(call.argument<String>("fileName"))
                        val whatsApp = call.argument<Boolean>("whatsapp") ?: false
                        val caption = call.argument<String>("caption")
                        if (bytes == null) result.error("bad_args", "PDF bytes missing", null)
                        else result.success(sharePdf(bytes, name, caption, whatsApp))
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        val whatsApp = call.argument<Boolean>("whatsapp") ?: false
                        if (text.isNullOrBlank()) result.error("bad_args", "Reminder text missing", null)
                        else result.success(shareText(text, whatsApp))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("billing_failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun updatesDir(): File = File(cacheDir, "updates").apply { mkdirs() }
    private fun billsDir(): File = File(cacheDir, "bills").apply { mkdirs() }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    /** Returns "started" when the system installer opened, or "permission_required". */
    private fun installApk(file: File): String {
        val apk = file.canonicalFile
        // Only APKs that this app downloaded into its own update folder can be installed.
        require(apk.isFile && apk.name.endsWith(".apk") && apk.parentFile == updatesDir().canonicalFile) {
            "Downloaded update not found"
        }
        if (!canInstallPackages()) {
            openInstallSettings()
            return "permission_required"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "started"
    }

    private fun safePdfName(input: String?): String {
        val base = (input ?: "Vktrix-receipt.pdf")
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .take(100)
        return if (base.lowercase().endsWith(".pdf")) base else "$base.pdf"
    }

    private fun writeSharedPdf(bytes: ByteArray, name: String): File {
        // Keep the cache tidy; receipts can always be regenerated from the API.
        billsDir().listFiles()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1000L }
            ?.forEach { it.delete() }
        return File(billsDir(), name).apply { writeBytes(bytes) }
    }

    private fun whatsAppPackage(): String? = when {
        packageManager.getLaunchIntentForPackage("com.whatsapp") != null -> "com.whatsapp"
        packageManager.getLaunchIntentForPackage("com.whatsapp.w4b") != null -> "com.whatsapp.w4b"
        else -> null
    }

    private fun sharePdf(bytes: ByteArray, name: String, caption: String?, whatsApp: Boolean): String {
        val file = writeSharedPdf(bytes, name)
        val uri = FileProvider.getUriForFile(this, "$packageName.bills", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            if (!caption.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, caption)
            clipData = ClipData.newUri(contentResolver, name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (whatsApp) {
            val target = whatsAppPackage() ?: return "whatsapp_not_installed"
            intent.setPackage(target)
            startActivity(intent)
        } else {
            startActivity(Intent.createChooser(intent, "Share PDF bill"))
        }
        return "started"
    }

    private fun shareText(text: String, whatsApp: Boolean): String {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        if (whatsApp) {
            val target = whatsAppPackage() ?: return "whatsapp_not_installed"
            intent.setPackage(target)
            startActivity(intent)
        } else {
            startActivity(Intent.createChooser(intent, "Share payment reminder"))
        }
        return "started"
    }

    private fun startSavePdf(bytes: ByteArray, name: String, result: MethodChannel.Result) {
        if (pendingPdfResult != null) {
            result.error("save_in_progress", "Another PDF save is already open", null)
            return
        }
        pendingPdfBytes = bytes
        pendingPdfResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            startActivityForResult(intent, SAVE_PDF_REQUEST)
        } catch (e: Exception) {
            pendingPdfBytes = null
            pendingPdfResult = null
            result.error("save_failed", e.message ?: e.javaClass.simpleName, null)
        }
    }

    @Deprecated("Deprecated in Android; retained for the system document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SAVE_PDF_REQUEST) {
            val callback = pendingPdfResult
            val bytes = pendingPdfBytes
            pendingPdfResult = null
            pendingPdfBytes = null
            if (callback == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) {
                callback.success("cancelled")
                return
            }
            try {
                contentResolver.openOutputStream(data.data!!, "w")!!.use { it.write(bytes) }
                callback.success("saved")
            } catch (e: Exception) {
                callback.error("save_failed", e.message ?: e.javaClass.simpleName, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val UPDATER_CHANNEL = "com.vktrix.mobileapp/updater"
        private const val BILLING_CHANNEL = "com.vktrix.mobileapp/billing"
        private const val SAVE_PDF_REQUEST = 54127
    }
}
