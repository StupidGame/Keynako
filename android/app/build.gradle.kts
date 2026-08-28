plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = providers.environmentVariable("KEYNAKO_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("KEYNAKO_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("KEYNAKO_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("KEYNAKO_KEY_PASSWORD").orNull
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }

if (!hasReleaseSigning && releaseSigningValues.any { !it.isNullOrBlank() }) {
    throw GradleException(
        "Release signing requires KEYNAKO_KEYSTORE_PATH, KEYNAKO_STORE_PASSWORD, " +
            "KEYNAKO_KEY_ALIAS, and KEYNAKO_KEY_PASSWORD.",
    )
}

android {
    namespace = "io.github.StupidGame.azookey_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.StupidGame.azookey_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments += "-DZENZ_NATIVE_OPTIMIZED=ON"
            }
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            // Zenzai is consumed by the IME service, not by Flutter. Keeping the
            // files as native Android assets avoids a duplicate iOS app bundle copy.
            assets.srcDir("../../assets")
            // Android cannot consume the Swift converter package directly. Its
            // Apache-2.0 default dictionary is read by the native IME instead.
            assets.srcDir("../../third_party/azookey_dictionary_storage")
        }
    }

    androidResources {
        noCompress += "gguf"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(checkNotNull(releaseKeystorePath))
                storePassword = checkNotNull(releaseStorePassword)
                keyAlias = checkNotNull(releaseKeyAlias)
                keyPassword = checkNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            // CI creates a temporary keystore and supplies these values through
            // environment variables. Without them, Gradle emits an unsigned
            // release instead of silently using the public debug certificate.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

dependencies {
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
