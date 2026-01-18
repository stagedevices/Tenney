package com.tenney.core

import kotlin.math.min
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
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
            val inputHasId = (case.input as? JsonObject)?.containsKey("id") == true
            val expected = if (inputHasId) case.expected else case.expected.copy(id = actual.id)
            if (expected != actual) {
                 val msg = buildScaleDiff(case.id, expected, actual)
                println(msg)
                throw AssertionError(msg)
            }
        }
    }

    @Test
    fun tenneyScaleLegacyFixtures() {
        val text = FixtureLoader.loadText("json/tenney_scale.legacy.v1.json")
        val cases = json.decodeFromString<List<TenneyScaleFixtureCase>>(text)
        for (case in cases) {
            val actual = json.decodeFromJsonElement(TenneyScaleSerializer, case.input)
            val inputHasId = (case.input as? JsonObject)?.containsKey("id") == true
            val expected = if (inputHasId) case.expected else case.expected.copy(id = actual.id)
            if (expected != actual) {
                val msg = buildScaleDiff(case.id, expected, actual)
                println(msg)
                throw AssertionError(msg)
            }
        }
    }

    private fun buildScaleDiff(caseId: String, expected: TenneyScale, actual: TenneyScale): String {
        val diffs = mutableListOf<String>()
        fun diff(field: String, e: Any?, a: Any?) {
            if (e != a) diffs += "$field\n  expected=$e\n  actual=$a"
        }
        diff("id", expected.id, actual.id)
        diff("name", expected.name, actual.name)
        diff("descriptionText", expected.descriptionText, actual.descriptionText)
        diff("tags", expected.tags, actual.tags)
        diff("favorite", expected.favorite, actual.favorite)
        diff("lastPlayed", expected.lastPlayed, actual.lastPlayed)
        diff("referenceHz", expected.referenceHz, actual.referenceHz)
        diff("rootLabel", expected.rootLabel, actual.rootLabel)
        diff("periodRatio", expected.periodRatio, actual.periodRatio)
        diff("detectedLimit", expected.detectedLimit, actual.detectedLimit)
        diff("maxTenneyHeight", expected.maxTenneyHeight, actual.maxTenneyHeight)
        diff("author", expected.author, actual.author)

        if (expected.degrees != actual.degrees) {
            diffs += "degrees (size expected=${expected.degrees.size} actual=${actual.degrees.size})"
            val n = min(expected.degrees.size, actual.degrees.size)
            for (i in 0 until n) {
                if (expected.degrees[i] != actual.degrees[i]) {
                    diffs += "degrees[$i]\n  expected=${expected.degrees[i]}\n  actual=${actual.degrees[i]}"
                    break
                }
            }
        }

        return buildString {
            appendLine("case=$caseId")
            appendLine("diffs=${diffs.size}")
            diffs.forEach { appendLine(it) }
        }
    }
}
