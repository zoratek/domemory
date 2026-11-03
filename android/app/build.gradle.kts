plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.ezequielbrrt.domemory"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.ezequielbrrt.domemory"
        minSdk = 26
        targetSdk = 37
        versionCode = 9
        versionName = "1.2.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        debug {
            // No applicationIdSuffix: the Firebase project has one Android client,
            // registered as com.ezequielbrrt.domemory, and the google-services plugin
            // fails the build when the applicationId does not match one exactly.
            // Register a second client for `.debug` to get side-by-side installs back.
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures {
        compose = true
        // Unit selection must never send debug traffic to production AdMob placements.
        buildConfig = true
    }

    kotlin {
        jvmToolchain(21)
    }

    sourceSets {
        getByName("main") {
            // Lottie JSON lives once, at the repository root, and both apps read it in
            // place: iOS through a symlink under SupportingFiles/, Android through this
            // extra assets root. A single file per animation means the two platforms
            // cannot drift on frame count, colour or timing.
            assets.srcDir("../../assets/animations/game")
            // Leaderboard name translations, shared with iOS for the same reason.
            assets.srcDir("../../localization")
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    // Real vector icons for lock/help/verified/calendar/etc. (spec 14.3's "map each SF
    // Symbol to a Material Symbol"), replacing the emoji/plain-text glyphs the Levels and
    // Seasons screens used before this iOS visual-parity pass.
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.database)
    implementation(libs.firebase.auth)
    implementation(libs.firebase.analytics)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.google.mobile.ads)
    implementation(libs.google.ump)
    implementation(libs.google.code.scanner)
    implementation(libs.zxing.core)
    // Review policy, Play In-App Review bridge and the full-screen review invitation — the
    // Android counterpart of the iOS app's ReviewFlow package. Built from the submodule at
    // android/ReviewFlow-Android (see settings.gradle.kts); it re-exports play-review-ktx.
    implementation(project(":reviewflow"))
    // Notification permission primer — the Android counterpart of the iOS app's
    // NotificationPermissionKit package. Built from the submodule at
    // android/NotificationPermissionKit-Android (see settings.gradle.kts).
    implementation(project(":notificationpermissionkit"))
    implementation(libs.lottie.compose)
    // What's New screen, model and theme — the Android counterpart of the iOS app's
    // WhatsNewKit package. Built from the submodule at android/WhatsNewKit-Android (see
    // settings.gradle.kts); the version gate stays in services/whatsnew/WhatsNewManager.
    implementation(project(":whatsnewkit"))
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // Android stubs org.json in unit tests; this puts a real implementation on the
    // test classpath so fixtures can be parsed off the JVM.
    testImplementation(libs.json)
}
