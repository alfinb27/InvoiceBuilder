// :core:pdf ≈ InvoicePDF: draws a `PDFDocumentModel` with a `PDFTemplate` into a PDF (android.graphics.pdf +
// Canvas + StaticLayout, ≈ Core Text in UIGraphicsPDFRenderer). No database, no view models: a request in, bytes out.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.invoicebuilder.core.pdf"
    compileSdk = 37
    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all { it.systemProperty("spec.root", rootProject.projectDir.resolve("../spec").absolutePath) }
    }
}

kotlin { jvmToolchain(21) }

dependencies {
    api(project(":core:domain"))
    implementation(libs.zxing.core)
    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    // The renderer needs the real Android graphics stack: its tests run on a device or emulator. PDFBox reads the
    // text back out (≈ PDFKit's `page.string` in the iOS tests); it is a test-only dependency.
    androidTestImplementation(libs.pdfbox.android)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
}
