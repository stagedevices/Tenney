package com.tenney.lattice

import com.tenney.core.RatioRef
import kotlinx.serialization.Serializable
import kotlin.math.pow

object LatticeSelection {
    @Serializable
    data class LatticeCoord(val e3: Int, val e5: Int)

    @Serializable
    data class GhostMonzo(val e3: Int, val e5: Int, val p: Int, val eP: Int)

    fun selectionRefs(
        pivot: LatticeCoord,
        axisShift: Map<Int, Int>,
        selectionOrderPlane: List<LatticeCoord>,
        selectionOrderGhosts: List<GhostMonzo>
    ): List<RatioRef> {
        val refs = mutableListOf<RatioRef>()

        selectionOrderPlane.forEach { coord ->
            val e3 = coord.e3 + pivot.e3 + (axisShift[3] ?: 0)
            val e5 = coord.e5 + pivot.e5 + (axisShift[5] ?: 0)
            val p = (if (e3 > 0) 3.0.pow(e3).toInt() else 1) *
                (if (e5 > 0) 5.0.pow(e5).toInt() else 1)
            val q = (if (e3 < 0) 3.0.pow(-e3).toInt() else 1) *
                (if (e5 < 0) 5.0.pow(-e5).toInt() else 1)
            refs.add(RatioRef.of(p = p, q = q, octave = 0, monzo = mapOf(3 to e3, 5 to e5)))
        }

        selectionOrderGhosts.forEach { ghost ->
            val e3 = ghost.e3
            val e5 = ghost.e5
            val eP = ghost.eP
            val prime = ghost.p
            val pNum = (if (e3 > 0) 3.0.pow(e3).toInt() else 1) *
                (if (e5 > 0) 5.0.pow(e5).toInt() else 1) *
                (if (eP > 0) prime.toDouble().pow(eP).toInt() else 1)
            val qDen = (if (e3 < 0) 3.0.pow(-e3).toInt() else 1) *
                (if (e5 < 0) 5.0.pow(-e5).toInt() else 1) *
                (if (eP < 0) prime.toDouble().pow(-eP).toInt() else 1)
            val monzo = mutableMapOf(3 to e3, 5 to e5)
            monzo[prime] = eP
            refs.add(RatioRef.of(p = pNum, q = qDen, octave = 0, monzo = monzo))
        }

        return refs
    }
}
