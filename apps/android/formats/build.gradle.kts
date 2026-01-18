plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
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
