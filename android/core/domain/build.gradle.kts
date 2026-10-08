// :core:domain ≈ InvoiceCore: pure Kotlin on the JVM (no Android SDK), so its tests run in seconds.
// The tests read spec/fixtures straight from the repository, like the Swift tests do.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)
}

// src/main/resources/spec: the runtime spec files (tax configs, reference data, PDF labels and layouts, fonts,
// design tokens), copied by `make sync-spec` exactly as for the iOS bundles (≈ a package's bundled resources).

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.launcher)
}

tasks.test {
    useJUnitPlatform()
    systemProperty("spec.root", rootProject.projectDir.resolve("../spec").absolutePath)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
