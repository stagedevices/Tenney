import org.gradle.api.tasks.testing.logging.TestExceptionFormat

subprojects {
    tasks.withType<Test>().configureEach {
        testLogging {
            // Make AssertionError messages visible in CI output.
            exceptionFormat = TestExceptionFormat.FULL
            showExceptions = true
            showCauses = true
            showStackTraces = true
            showStandardStreams = true
            events("failed")
        }
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    implementation(project(":core"))
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}

sourceSets {
    test {
        resources.srcDir(rootProject.file("../../shared/fixtures"))
    }
}

tasks.withType<Test>().configureEach {
    useJUnit()
}
