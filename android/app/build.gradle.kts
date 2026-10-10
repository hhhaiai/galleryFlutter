plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.gemma_local_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.gemma_local_app"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Match Google AI Edge Gallery. LiteRT-LM JNI reflects into Kotlin
            // config classes during createConversation(); R8 obfuscation can
            // make nativeCreateConversation abort with "mid == null".
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Validate the latest standalone LiteRT-LM release as one isolated
    // variable against the already verified 7fa1... model revision. The
    // preceding 0.11.0 candidate crashed in Pixel 8 GPU vision initialization;
    // this version is retained only if text, image, audio, and Skills all pass
    // the same device probes.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.14.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
