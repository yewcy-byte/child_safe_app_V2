plugins {
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://jitpack.io")
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(project.name))

    if (name != "app") {
        evaluationDependsOn(":app")
    }

    buildscript {
        configurations.matching { it.name == "classpath" }.configureEach {
            resolutionStrategy.eachDependency {
                if (requested.group == "org.jetbrains.kotlin" &&
                    requested.name == "kotlin-gradle-plugin") {
                    useVersion("2.1.0")
                    because("Legacy plugins pin very old Kotlin plugin versions incompatible with AGP 8+")
                }
            }
        }
    }

    plugins.withType<com.android.build.gradle.BasePlugin> {
        extensions.configure<com.android.build.gradle.BaseExtension> {
            if (namespace == null) {
                namespace = "com.example.${project.name.replace('-', '_')}"
            }
        }
    }
}