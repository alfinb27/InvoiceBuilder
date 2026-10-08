// :core:data ≈ InvoiceData: Room over the spec's SQLite schema. The file is created and migrated by the spec's SQL
// (like GRDB on iOS); Room's DAOs give typed queries and Flow observation (≈ ValueObservation).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "app.invoicebuilder.core.data"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions {
        // Robolectric runs the Android SQLite on the JVM (no emulator), like `swift test` for InvoiceData.
        unitTests.isIncludeAndroidResources = true
        unitTests.all { it.systemProperty("spec.root", rootProject.projectDir.resolve("../spec").absolutePath) }
    }
}

kotlin {
    jvmToolchain(21)
}

ksp {
    arg("room.generateKotlin", "true")
}

dependencies {
    api(project(":core:domain"))
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.turbine)
}
