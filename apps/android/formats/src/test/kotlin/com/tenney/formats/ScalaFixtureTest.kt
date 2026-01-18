package com.tenney.formats

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class ScalaFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        classDiscriminator = "type"
    }

    @Serializable
    private data class ScalaParseCase(
        val id: String,
        val text: String,
        val expected: ScalaFixture
    )

    @Serializable
    private data class ScalaSerializeCase(
        val id: String,
        val input: ScalaFixture,
        val expected: String
    )

    @Serializable
    private data class ScalaFixture(
        val description: String,
        val entries: List<ScalaEntryFixture>
    )

    @Serializable
    private sealed class ScalaEntryFixture {
        abstract fun toEntry(): ScalaScale.Entry

        @Serializable
        @SerialName("ratio")
        data class Ratio(val n: Int, val d: Int) : ScalaEntryFixture() {
            override fun toEntry(): ScalaScale.Entry = ScalaScale.Entry.Ratio(ScalaScale.Rational.of(n, d))
        }

        @Serializable
        @SerialName("cents")
        data class Cents(val value: Double) : ScalaEntryFixture() {
            override fun toEntry(): ScalaScale.Entry = ScalaScale.Entry.Cents(value)
        }
    }

    @Test
    fun scalaParseFixtures() {
        val text = FixtureLoader.loadText("formats/scala_parse.v1.json")
        val cases = json.decodeFromString<List<ScalaParseCase>>(text)
        for (case in cases) {
            val parsed = ScalaScale.parse(case.text)
            assertEquals("case=${case.id}", case.expected.description, parsed.description)
            assertEquals("case=${case.id}", case.expected.entries.map { it.toEntry() }, parsed.entries)
        }
    }

    @Test
    fun scalaSerializeFixtures() {
        val text = FixtureLoader.loadText("formats/scala_serialize.v1.json")
        val cases = json.decodeFromString<List<ScalaSerializeCase>>(text)
        for (case in cases) {
            val scale = ScalaScale(
                description = case.input.description,
                entries = case.input.entries.map { it.toEntry() }
            )
            assertEquals("case=${case.id}", case.expected, scale.serialize())
        }
    }
}
