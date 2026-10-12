// :core:drive ≈ InvoiceDrive: automatic backup to the user's Google Drive (spec/backup.md §7, ADR-0021), behind
// :core:domain's `CloudBackupDestination`. Google Identity's AuthorizationClient hands out tokens for the one
// `drive.file` scope; Drive REST v3 goes through `HttpTransport` (HttpURLConnection), so requests are tested on the JVM.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "app.invoicebuilder.core.drive"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(21) }

dependencies {
    api(project(":core:domain"))
    implementation(libs.play.services.auth)
    implementation(libs.kotlinx.coroutines.play.services)
    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
}
