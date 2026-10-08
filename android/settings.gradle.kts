// The Android app (Phase 7): Gradle modules mirror the iOS packages one to one (android/CLAUDE.md).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "InvoiceBuilder"

include(":core:domain")
include(":core:data")
include(":core:pdf")
include(":core:billing")
include(":core:designsystem")
