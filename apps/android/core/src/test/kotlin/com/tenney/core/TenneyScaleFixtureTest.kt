package com.tenney.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement
import org.junit.Assert.assertEquals
import org.junit.Test

class TenneyScaleFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class TenneyScaleFixtureCase(
        val id: String,
        val input: JsonElement,
        val expected: TenneyScale
    )

    @Test
    fun tenneyScaleFixtures() {
        val text = FixtureLoader.loadText("json/tenney_scale.v1.json")
        val cases = json.decodeFromString<List<TenneyScaleFixtureCase>>(text)
        for (case in cases) {
            val actual = json.decodeFromJsonElement(TenneyScaleSerializer, case.input)
            assertEquals("case=${case.id}", case.expected, actual)
        }
    }

    @Test
    fun tenneyScaleLegacyFixtures() {
        val text = FixtureLoader.loadText("json/tenney_scale.legacy.v1.json")
        val cases = json.decodeFromString<List<TenneyScaleFixtureCase>>(text)
        for (case in cases) {
            val actual = json.decodeFromJsonElement(TenneyScaleSerializer, case.input)
            assertEquals("case=${case.id}", case.expected, actual)
        }
    }
}
