package com.vktrix.mobileapp

import android.content.ActivityNotFoundException
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
                        if (path == null) {
                            result.error("bad_args", "APK path missing", null)
                        } else {
                            result.success(installApk(File(path)))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("updater_failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun updatesDir(): File = File(cacheDir, "updates").apply { mkdirs() }

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

    companion object {
        private const val UPDATER_CHANNEL = "com.vktrix.mobileapp/updater"
    }
}
