import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("io.sentry.android.gradle")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "com.songspot.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.songspot.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// Uploads the R8 mapping file so the Java/Kotlin frames in Android crashes are
// readable in Sentry. sentry_dart_plugin handles the Dart and native symbols
// but has no ProGuard support, which is why this plugin is needed on top.
//
// Everything that would alter the running app is switched off: this is a
// build-time upload step only. Reads SENTRY_AUTH_TOKEN from the environment,
// as the Fastlane lanes already export it.
sentry {
    org.set(System.getenv("SENTRY_ORG") ?: "eowin")
    projectName.set(System.getenv("SENTRY_PROJECT") ?: "songspot-mobile")

    // Upload only on release builds that actually have a token to upload
    // with, so a local `flutter build --release` without SENTRY_AUTH_TOKEN
    // still succeeds instead of failing in sentry-cli.
    autoUploadProguardMapping.set(
        !System.getenv("SENTRY_AUTH_TOKEN").isNullOrBlank() &&
            gradle.startParameter.taskNames.any { it.contains("Release") }
    )
    includeProguardMapping.set(true)

    // sentry_dart_plugin already uploads these; doing it twice is wasted
    // build time.
    uploadNativeSymbols.set(false)

    // sentry_flutter installs and configures the Android SDK itself. Letting
    // this plugin add its own dependency or rewrite bytecode would duplicate
    // the integration.
    autoInstallation.enabled.set(false)
    tracingInstrumentation.enabled.set(false)
}
