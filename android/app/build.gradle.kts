import java.io.FileInputStream
import java.util.Properties

// ============================================================
// Android app module — Lumina Fortune (Prism gray-flow enabled)
// ============================================================
// ⚠️ Keep `namespace` and `applicationId` in sync with:
//   • lib/prism/settings.dart → PrismSettings.bundleId
//   • android/app/google-services.json → client.package_name
//   • android/app/src/main/kotlin/**/MainActivity.kt package
// ============================================================

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin must come after the Android and
    // Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Apply the Google Services plugin only once google-services.json
// is present. Lets the project build before Firebase creds are
// supplied (the gate falls back to the native game path anyway).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load release signing config from android/key.properties if
// present.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.luminafortune.luminagame"

    // ⚠️ AI AGENT: keep minSdk at the LOWEST value the current
    // Firebase / AppsFlyer / flutter_local_notifications stack
    // supports (API 26 as of the pins in pubspec.yaml). Raising
    // minSdk slices eligible users off the campaign.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications 18+ (java.time.*).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.luminafortune.luminagame"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
