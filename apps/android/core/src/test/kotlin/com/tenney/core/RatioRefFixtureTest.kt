package com.tenney.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class RatioRefFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class RatioRefFixtureInput(
        val p: Int,
        val q: Int,
        val octave: Int = 0,
        val monzo: Map<Int, Int> = emptyMap()
    )

    @Serializable
    private data class RatioRefFixtureCase(
        val id: String,
        val input: RatioRefFixtureInput,
        val expected: RatioRef
    )

    @Test
    fun ratioRefFixtures() {
        val text = FixtureLoader.loadText("json/ratio_ref.v1.json")
        val cases = json.decodeFromString<List<RatioRefFixtureCase>>(text)
        for (case in cases) {
            val actual = RatioRef.of(
                p = case.input.p,
                q = case.input.q,
                octave = case.input.octave,
                monzo = case.input.monzo
            )
            assertEquals("case=${case.id}", case.expected, actual)
        }
    }
}
