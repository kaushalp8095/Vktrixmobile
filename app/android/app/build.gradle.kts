import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("../../keystore/key.properties")
    if (f.exists()) load(FileInputStream(f))
}

// Release builds MUST be signed with the persistent key: Android only installs an update
// over the existing app when both APKs share the same signing certificate. A debug-signed
// "release" silently broke in-app updates ("App not installed") and could never be fixed
// later for installed users, so a missing keystore is now a build failure, not a fallback.
val releaseKeystoreProperty = keystoreProperties.getProperty("storeFile")
val releaseKeystoreFile = releaseKeystoreProperty?.let { rootProject.file(it) }
val releaseKeystoreReady = releaseKeystoreFile?.isFile == true
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseBuildRequested && !releaseKeystoreReady) {
    throw GradleException(
        "Release build needs a signing key. Create keystore/key.properties with " +
            "storeFile, storePassword, keyAlias and keyPassword (see README) or set the " +
            "ANDROID_KEYSTORE_BASE64 secrets in CI. Refusing to ship a debug-signed build."
    )
}

android {
    namespace = "com.vktrix.mobileapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vktrix.mobileapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // mobile_scanner 7.x (CameraX 1.6) needs API 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseKeystoreReady) {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key: a debug-signed "release" cannot be updated in place.
            signingConfig = if (releaseKeystoreReady) {
                signingConfigs.getByName("release")
            } else {
                // Unreachable for release tasks (checked above); keep debug builds working.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider: hands the downloaded update APK to the system installer.
    implementation("androidx.core:core:1.13.1")
}
