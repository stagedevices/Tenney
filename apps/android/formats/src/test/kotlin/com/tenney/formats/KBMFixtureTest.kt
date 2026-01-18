package com.tenney.formats

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class KBMFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class KBMParseCase(
        val id: String,
        val text: String,
        val expected: KeyboardMappingFixture
    )

    @Serializable
    private data class KBMSerializeCase(
        val id: String,
        val input: KeyboardMappingFixture,
        val expected: String
    )

    @Serializable
    private data class KeyboardMappingFixture(
        val mappingSize: Int,
        val firstMIDINote: Int,
        val lastMIDINote: Int,
        val middleNote: Int,
        val referenceDegreeIndex: Int,
        val referenceFrequencyHz: Double,
        val degreeOfNote: List<Int>
    )

    @Test
    fun kbmParseFixtures() {
        val text = FixtureLoader.loadText("formats/kbm_parse.v1.json")
        val cases = json.decodeFromString<List<KBMParseCase>>(text)
        for (case in cases) {
            val parsed = KeyboardMapping.parse(case.text)
            assertEquals("case=${case.id}", case.expected.mappingSize, parsed.mappingSize)
            assertEquals("case=${case.id}", case.expected.firstMIDINote, parsed.firstMIDINote)
            assertEquals("case=${case.id}", case.expected.lastMIDINote, parsed.lastMIDINote)
            assertEquals("case=${case.id}", case.expected.middleNote, parsed.middleNote)
            assertEquals("case=${case.id}", case.expected.referenceDegreeIndex, parsed.referenceDegreeIndex)
            assertEquals("case=${case.id}", case.expected.referenceFrequencyHz, parsed.referenceFrequencyHz, 1e-9)
            assertEquals("case=${case.id}", case.expected.degreeOfNote, parsed.degreeOfNote)
        }
    }

    @Test
    fun kbmSerializeFixtures() {
        val text = FixtureLoader.loadText("formats/kbm_serialize.v1.json")
        val cases = json.decodeFromString<List<KBMSerializeCase>>(text)
        for (case in cases) {
            val mapping = KeyboardMapping(
                mappingSize = case.input.mappingSize,
                firstMIDINote = case.input.firstMIDINote,
                lastMIDINote = case.input.lastMIDINote,
                middleNote = case.input.middleNote,
                referenceFrequencyHz = case.input.referenceFrequencyHz,
                referenceDegreeIndex = case.input.referenceDegreeIndex,
                degreeOfNote = case.input.degreeOfNote
            )
            assertEquals("case=${case.id}", case.expected, mapping.serialize())
        }
    }
}
