package com.tenney.formats

import java.io.InputStream

object FixtureLoader {
    fun loadText(path: String): String {
        val stream: InputStream = FixtureLoader::class.java.classLoader
            ?.getResourceAsStream(path)
            ?: error("Fixture not found: $path")
        return stream.bufferedReader().use { it.readText() }
    }
}
