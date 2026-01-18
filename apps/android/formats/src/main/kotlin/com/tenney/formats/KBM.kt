package com.tenney.formats

data class KeyboardMapping(
    val mappingSize: Int,
    val firstMIDINote: Int,
    val lastMIDINote: Int,
    val middleNote: Int,
    val referenceFrequencyHz: Double,
    val referenceDegreeIndex: Int,
    val degreeOfNote: List<Int>
) {
    companion object {
        fun parse(text: String): KeyboardMapping {
            var lines = text.split(Regex("\\R")).map { it.trim() }
            lines = lines.filter { it.isNotEmpty() && !it.startsWith("!") }

            fun requireInt(index: Int, name: String): Int {
                val token = lines.getOrNull(index)?.split(Regex("\\s+"))?.firstOrNull()
                return token?.toIntOrNull() ?: error("Missing $name")
            }

            fun requireDouble(index: Int, name: String): Double {
                val token = lines.getOrNull(index)?.split(Regex("\\s+"))?.firstOrNull()
                return token?.toDoubleOrNull() ?: error("Missing $name")
            }

            val mappingSize = requireInt(0, "mapping size")
            val firstMIDINote = requireInt(1, "first MIDI note")
            val lastMIDINote = requireInt(2, "last MIDI note")
            val middleNote = requireInt(3, "middle note")
            val referenceDegreeIndex = requireInt(4, "reference degree")
            val referenceFrequencyHz = requireDouble(5, "reference frequency")

            val degreeOfNote = mutableListOf<Int>()
            var idx = 6
            repeat(mappingSize) {
                val token = lines.getOrNull(idx)?.split(Regex("\\s+"))?.firstOrNull()
                degreeOfNote.add(token?.toIntOrNull() ?: -1)
                idx += 1
            }

            return KeyboardMapping(
                mappingSize = mappingSize,
                firstMIDINote = firstMIDINote,
                lastMIDINote = lastMIDINote,
                middleNote = middleNote,
                referenceFrequencyHz = referenceFrequencyHz,
                referenceDegreeIndex = referenceDegreeIndex,
                degreeOfNote = degreeOfNote
            )
        }
    }

    fun serialize(): String {
        val out = mutableListOf<String>()
        out.add("! Tenney .kbm")
        out.add(mappingSize.toString())
        out.add(firstMIDINote.toString())
        out.add(lastMIDINote.toString())
        out.add(middleNote.toString())
        out.add(referenceDegreeIndex.toString())
        out.add(String.format("%.6f", referenceFrequencyHz))
        degreeOfNote.forEach { out.add(it.toString()) }
        return out.joinToString("\n")
    }
}
