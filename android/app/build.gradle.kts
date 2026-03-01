plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = java.util.Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}
val mapsApiKey = localProperties.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY")
    ?: ""

android {
        ndkVersion = "28.2.13676358"

    // This MUST match your package name in MainActivity.kt
    namespace = "com.example.child_safe_app"
    
    // 36 is correct for RenderEffect and path_provider_android
    compileSdk = 36
    buildToolsVersion = "35.0.0" // <--- ADD THIS LINE

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    aaptOptions {
        // This prevents TFLite files from being compressed
        noCompress += listOf("tflite", "lite")
    }

    defaultConfig {
        applicationId = "com.example.child_safe_app"
        
        // TensorFlow Lite requires minSdk 21+
        minSdk = flutter.minSdkVersion
        targetSdk = 35 // Recommended stable target for 2026
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }

        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey

    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), 
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // TensorFlow Lite AAR - includes native libraries (libtensorflowlite_c.so)
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.14.0")

    // NSFW helper (same engine used by flutter_nsfw plugin)
    implementation("io.github.devzwy:nsfw:1.5.1")
    
    // GIF animation support from Maven Central
    implementation("pl.droidsonroids.gif:android-gif-drawable:1.2.28")
    
    // Kotlin Coroutines and Lifecycle
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    
    // Google Play Services for Location
    implementation("com.google.android.gms:play-services-location:21.1.0")
    
    // Firebase for native Android service
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    
    // Modern Kotlin adds the stdlib automatically. 
    // Only add specific libraries (like TFLite) here.
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    doLast {
        val generatedApk = layout.buildDirectory.file("outputs/flutter-apk/app-debug.apk").get().asFile
        if (generatedApk.exists()) {
            val flutterExpectedDir = rootProject.projectDir.parentFile
                .resolve("build/app/outputs/flutter-apk")
            flutterExpectedDir.mkdirs()
            generatedApk.copyTo(
                flutterExpectedDir.resolve("app-debug.apk"),
                overwrite = true,
            )
        }
    }
}



// REMOVE the subprojects block from here. 
// It belongs ONLY in the root android/build.gradle.kts file.
