package com.tenney.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
class TenneyScaleDerivedTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class DerivedExpected(val detectedLimit: Int, val maxTenneyHeight: Int)

    @Serializable
    private data class DerivedCase(
        val id: String,
        val degrees: List<RatioRef>,
        val expected: DerivedExpected
    )

    @Test
    fun derivedFixtures() {
        val text = FixtureLoader.loadText("domain/tenney_scale_derived.v1.json")
        val cases = json.decodeFromString<List<DerivedCase>>(text)
        for (case in cases) {
            val detected = TenneyScaleDerived.detectedLimit(case.degrees)
            val height = TenneyScaleDerived.maxTenneyHeight(case.degrees)
            assertEquals("case=${case.id}", case.expected.detectedLimit, detected)
            assertEquals("case=${case.id}", case.expected.maxTenneyHeight, height)
        }
    }
}
