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

val admobAndroidProductionAppId =
    (project.findProperty("ADMOB_ANDROID_APP_ID") as String?)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: System.getenv("ADMOB_ANDROID_APP_ID")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        ?: "ca-app-pub-1153776263866015~1165718873"
val admobAndroidTestAppId = "ca-app-pub-3940256099942544~3347511713"
val admobGoogleSamplePublisherPrefix = "ca-app-pub-3940256099942544"
val admobAndroidAppIdPattern = Regex("^ca-app-pub-\\d+~\\d+$")
if (
    releaseBuildRequested &&
    (admobAndroidProductionAppId == null ||
        !admobAndroidAppIdPattern.matches(admobAndroidProductionAppId) ||
        admobAndroidProductionAppId.startsWith(admobGoogleSamplePublisherPrefix))
) {
    error(
        "A production AdMob Android App ID is required for release builds. " +
            "Set ADMOB_ANDROID_APP_ID to the ca-app-pub-...~... value from AdMob."
    )
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
        manifestPlaceholders["ADMOB_APP_ID"] = admobAndroidTestAppId
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
        debug {
            // Never let a production shell variable turn a debug build into a
            // source of live ad traffic.
            manifestPlaceholders["ADMOB_APP_ID"] = admobAndroidTestAppId
        }
        release {
            // Debug builds never need the upload key. Release tasks fail above
            // with a clear message rather than silently creating an unsigned AAB.
            signingConfig = signingConfigs.findByName("release")
            manifestPlaceholders["ADMOB_APP_ID"] =
                admobAndroidProductionAppId ?: admobAndroidTestAppId
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
