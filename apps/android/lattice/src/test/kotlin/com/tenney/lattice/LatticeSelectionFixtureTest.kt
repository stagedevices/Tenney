package com.tenney.lattice

import com.tenney.core.RatioRef
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class LatticeSelectionFixtureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Serializable
    private data class SelectionCase(
        val id: String,
        val pivot: LatticeSelection.LatticeCoord,
        val axisShift: Map<Int, Int>,
        val selectionOrderPlane: List<LatticeSelection.LatticeCoord>,
        val selectionOrderGhosts: List<LatticeSelection.GhostMonzo>,
        val expected: List<RatioRef>
    )

    @Test
    fun selectionRefsFixtures() {
        val text = FixtureLoader.loadText("lattice/selection_refs.v1.json")
        val cases = json.decodeFromString<List<SelectionCase>>(text)
        for (case in cases) {
            val actual = LatticeSelection.selectionRefs(
                pivot = case.pivot,
                axisShift = case.axisShift,
                selectionOrderPlane = case.selectionOrderPlane,
                selectionOrderGhosts = case.selectionOrderGhosts
            )
            assertEquals("case=${case.id}", case.expected, actual)
        }
    }
}
