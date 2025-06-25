plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.kml_explorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "26.1.10909125"
    // ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.kml_explorer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file("kml_explorer.keystore")
            storePassword = "kml_explorer_2024"
            keyAlias = "kml_explorer_key"
            keyPassword = "kml_explorer_2024"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 添加APK输出配置
    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "kml_explorer-${variant.name}.apk"
        }
    }
}

dependencies {
    // 移除重复的Google Play Core依赖，只保留一个
    implementation("com.google.android.play:app-update:2.1.0")
    // 移除这行：implementation("com.google.android.play:core:1.10.3")
    // 移除这行：implementation("com.google.android.play:app-update-ktx:2.1.0")
}

flutter {
    source = "../.."
}
