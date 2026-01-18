package com.tenney.core

import kotlin.math.abs

object TenneyScaleDerived {
    fun detectedLimit(degrees: List<RatioRef>): Int {
        var maxPrime = 2
        for (ref in degrees) {
            if (ref.monzo.isNotEmpty()) {
                val candidate = ref.monzo.keys.filter { it != 2 }.maxOrNull() ?: 2
                if (candidate > maxPrime) maxPrime = candidate
            } else {
                val (rp, rq) = RatioMath.reduced(ref.p, ref.q)
                maxPrime = maxOf(maxPrime, maxOddPrimeFactor(rp))
                maxPrime = maxOf(maxPrime, maxOddPrimeFactor(rq))
            }
        }
        return maxPrime
    }

    fun maxTenneyHeight(degrees: List<RatioRef>): Int {
        return degrees.maxOfOrNull { RatioMath.tenneyHeight(it.p, it.q) } ?: 1
    }

    private fun maxOddPrimeFactor(value: Int): Int {
        var x = abs(value)
        if (x <= 1) return 2
        while (x % 2 == 0) x /= 2
        if (x <= 1) return 2
        var maxP = 2
        var f = 3
        while (f * f <= x) {
            while (x % f == 0) {
                maxP = f
                x /= f
            }
            f += 2
        }
        if (x > 1) maxP = maxOf(maxP, x)
        return maxP
    }
}
