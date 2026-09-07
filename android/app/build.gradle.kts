import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyProperties = Properties()
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseBuildRequested && !releaseKeyPropertiesFile.exists()) {
    error(
        "Release signing is not configured. Copy android/key.properties.example " +
            "to android/key.properties and provide the private upload-key values."
    )
}
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

android {
    namespace = "com.abu3meer.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.abu3meer.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // Use a project-specific debug identity so Firebase/Google OAuth
            // does not collide with the legacy Firebase project's debug key.
            // The key is intentionally not committed. Fresh clones fall back
            // to Gradle's standard per-user debug key until a local project
            // key is generated and its SHA fingerprints are added to Firebase.
            val projectDebugKeystore = file("abu3meer-debug.keystore")
            if (projectDebugKeystore.exists()) {
                storeFile = projectDebugKeystore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
        if (releaseKeyPropertiesFile.exists()) {
            create("release") {
                val storePath = releaseKeyProperties.getProperty("storeFile")
                    ?: error("android/key.properties is missing storeFile")
                storeFile = rootProject.file(storePath)
                storePassword = releaseKeyProperties.getProperty("storePassword")
                    ?: error("android/key.properties is missing storePassword")
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                    ?: error("android/key.properties is missing keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
                    ?: error("android/key.properties is missing keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug builds never need the upload key. Release tasks fail above
            // with a clear message rather than silently creating an unsigned AAB.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        freeCompilerArgs.add("-Xannotation-default-target=param-property")
    }
}

flutter {
    source = "../.."
}
