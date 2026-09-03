// ============================================================
// Root Gradle configuration — Lumina Fortune
// ============================================================
// Some plugins ship with `compileSdk = 34` while their transitive
// deps (e.g. `flutter_plugin_android_lifecycle`) demand 36. We
// override compileSdk to 36 for every Android library subproject
// so `CheckAarMetadata` never aborts. See pitfalls doc §2.
//
// The override MUST be registered BEFORE
// `evaluationDependsOn(":app")` — that block eagerly evaluates
// every subproject, and a later `afterEvaluate` would fail with
// "Cannot run Project.afterEvaluate(Action) when the project is
// already evaluated" (pitfalls §7).
// ============================================================

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Force every Android library plugin to compile against 36+.
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
