plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Must match the package `flutter create --org com.darkroom` generates
    // for MainActivity (com.darkroom.darkroom).
    namespace = "com.darkroom.darkroom"
    // flutter_local_notifications needs compileSdk >= 35.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on old APIs).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.darkroom.darkroom"
        // ffmpeg_kit_flutter_new_min requires API 24+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Release builds are signed with the private upload key when CI hands it
    // over (GitHub secrets ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD,
    // decoded to DARKROOM_KEYSTORE by the workflow). Without it (local builds,
    // forks) they fall back to the public test key, which only installs over
    // other test-key builds.
    val uploadKeystore = System.getenv("DARKROOM_KEYSTORE")?.takeIf { it.isNotBlank() }
    signingConfigs {
        create("test") {
            storeFile = file("darkroom-test.jks")
            storePassword = "darkroom"
            keyAlias = "darkroom"
            keyPassword = "darkroom"
        }
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("DARKROOM_KEYSTORE_PASSWORD")
                keyAlias = "upload"
                keyPassword = System.getenv("DARKROOM_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (uploadKeystore != null) "upload" else "test")
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
    // FileProvider for ShareThumbnailProvider (share_plus uses the same).
    implementation("androidx.core:core-ktx:1.16.0")
}

flutter {
    source = "../.."
}
