package com.tenney.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
class RatioMathFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class RatioMathFixtureCase(
        val id: String,
        val fn: String,
        val input: JsonObject,
        val expected: JsonElement
    )

    @Test
    fun ratioMathFixtures() {
        val text = FixtureLoader.loadText("math/ratio_math.v1.json")
        val cases = json.decodeFromString<List<RatioMathFixtureCase>>(text)
        for (case in cases) {
            when (case.fn) {
                "gcd" -> {
                    val a = case.input["a"].asInt()
                    val b = case.input["b"].asInt()
                    assertEquals("case=${case.id}", case.expected.asInt(), RatioMath.gcd(a, b))
                }
                "reduced" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    val expected = case.expected.asObject()
                    assertEquals("case=${case.id}", expected["p"].asInt(), RatioMath.reduced(p, q).first)
                    assertEquals("case=${case.id}", expected["q"].asInt(), RatioMath.reduced(p, q).second)
                }
                "canonicalPQUnit" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    val expected = case.expected.asObject()
                    assertEquals("case=${case.id}", expected["p"].asInt(), RatioMath.canonicalPQUnit(p, q).first)
                    assertEquals("case=${case.id}", expected["q"].asInt(), RatioMath.canonicalPQUnit(p, q).second)
                }
                "unitLabel" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    assertEquals("case=${case.id}", case.expected.asString(), RatioMath.unitLabel(p, q))
                }
                "tenneyHeight" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    assertEquals("case=${case.id}", case.expected.asInt(), RatioMath.tenneyHeight(p, q))
                }
                "centsForRatio" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    assertEquals("case=${case.id}", case.expected.asDouble(), RatioMath.centsForRatio(p, q), 1e-6)
                }
                "ratioToHz" -> {
                    val p = case.input["p"].asInt()
                    val q = case.input["q"].asInt()
                    val octave = case.input["octave"].asInt()
                    val rootHz = case.input["rootHz"].asDouble()
                    val centsError = case.input["centsError"].asInt()
                    assertEquals(
                        "case=${case.id}",
                        case.expected.asDouble(),
                        RatioMath.ratioToHz(p, q, octave, rootHz, centsError),
                        1e-9
                    )
                }
                "foldToAudible" -> {
                    val f = case.input["f"].asDouble()
                    val minHz = case.input["minHz"].asDouble()
                    val maxHz = case.input["maxHz"].asDouble()
                    assertEquals(
                        "case=${case.id}",
                        case.expected.asDouble(),
                        RatioMath.foldToAudible(f, minHz, maxHz),
                        1e-9
                    )
                }
                "centsFromET" -> {
                    val freqHz = case.input["freqHz"].asDouble()
                    val refHz = case.input["refHz"].asDouble()
                    val expected = case.expected.asDouble()
                    val actual = RatioMath.centsFromET(freqHz, refHz)
                    assertTrue("case=${case.id}", abs(actual - expected) <= 1e-6)
                }
                "nearestETSemiIndex" -> {
                    val freqHz = case.input["freqHz"].asDouble()
                    val refHz = case.input["refHz"].asDouble()
                    assertEquals("case=${case.id}", case.expected.asInt(), RatioMath.nearestETSemiIndex(freqHz, refHz))
                }
                else -> error("Unknown fn ${case.fn}")
            }
        }
    }

    private fun JsonElement?.asPrimitive(): JsonPrimitive =
        this as? JsonPrimitive ?: error("Expected JsonPrimitive, got ${this?.let { it::class.simpleName } ?: "null"}")

    private fun JsonElement?.asObject(): JsonObject =
        this as? JsonObject ?: error("Expected JsonObject, got ${this?.let { it::class.simpleName } ?: "null"}")

    private fun JsonElement?.asInt(): Int =
        asPrimitive().content.toIntOrNull()
           ?: error("Expected int, got '${asPrimitive().content}'")

    private fun JsonElement?.asDouble(): Double =
        asPrimitive().content.toDoubleOrNull()
            ?: error("Expected double, got '${asPrimitive().content}'")

    private fun JsonElement?.asString(): String = asPrimitive().content
}
