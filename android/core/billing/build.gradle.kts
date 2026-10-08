// :core:billing ≈ InvoiceBilling: the unlock through Play Billing (`spec/billing.md`), same state machine as iOS.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.invoicebuilder.core.billing"
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
    implementation(libs.billing)
    implementation(libs.blockstore)
    implementation(libs.kotlinx.coroutines.play.services)
    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
}
