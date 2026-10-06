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

    // Fixed test key so every build (Mac, Windows or the GitHub build) is
    // signed the same way and installs over the previous one without
    // wiping photos. Test-only: use a private key before publishing.
    signingConfigs {
        create("test") {
            storeFile = file("darkroom-test.jks")
            storePassword = "darkroom"
            keyAlias = "darkroom"
            keyPassword = "darkroom"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("test")
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
