plugins {
    id("com.android.application")
}

android {
    namespace = "com.retrolan.console"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.retrolan.console"
        minSdk = 21          // Android 5.0+ — NDK minimum; covers all Android TV/Google TV/ONN devices
        targetSdk = 34       // Android 14 — satisfies lint & runs on all current TV devices
        versionCode = 1
        versionName = "1.0.0"

        // Universal build: bundle arm64-v8a + x86_64 + armeabi-v7a so ONE APK works on
        // any Android TV / Google TV / ONN box — including 32-bit ARM devices like this ONN.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64", "armeabi-v7a") }
        externalNativeBuild {
            cmake { cFlags += "-std=c11" } // retro_core_jni.c is C
        }
    }

    signingConfigs {
        // REAL release keystore — some Android TV / Google TV installers reject debug-signed
        // APKs as "incompatible", so a proper release signature is required for max install success.
        create("release") {
            storeFile = file("$rootDir/../keystore/retrolan-release.keystore")
            storePassword = "retrolan123"
            keyAlias = "retrolan"
            keyPassword = "retrolan123"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = false; viewBinding = false }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties",
                "META-INF/versions/9/module-info.class",
            )
        }
    }

    externalNativeBuild {
        cmake { path = file("src/main/jni/CMakeLists.txt") }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    // 10-foot / TV UI
    implementation("androidx.leanback:leanback:1.0.0")
    implementation("androidx.tvprovider:tvprovider:1.1.0")
    // Ktor WebSocket server
    implementation("io.ktor:ktor-server-core-jvm:2.3.10")
    implementation("io.ktor:ktor-server-host-common:2.3.10")
    implementation("io.ktor:ktor-server-netty-jvm:2.3.10")
    implementation("io.ktor:ktor-server-websockets-jvm:2.3.10")
    implementation("io.ktor:ktor-network:2.3.10")
    // Ktor WebSocket client (emulator process relays controller input over localhost)
    implementation("io.ktor:ktor-client-core-jvm:2.3.10")
    implementation("io.ktor:ktor-client-cio-jvm:2.3.10")
    implementation("io.ktor:ktor-client-websockets-jvm:2.3.10")
    // JSON
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
