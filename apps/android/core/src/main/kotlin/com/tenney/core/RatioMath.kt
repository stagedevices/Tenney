package com.tenney.core

import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.round

object RatioMath {
    fun ratioToHz(p: Int, q: Int, octave: Int, rootHz: Double, centsError: Int): Double {
        if (!rootHz.isFinite() || rootHz <= 0.0) return Double.NaN
        if (p <= 0 || q <= 0) return Double.NaN

        val (cn, cd) = canonicalPQUnit(p, q)
        var hz = rootHz * (cn.toDouble() / cd.toDouble()) * 2.0.pow(octave.toDouble())
        if (centsError != 0) {
            hz *= 2.0.pow(centsError / 1200.0)
        }
        return hz
    }

    fun gcd(a: Int, b: Int): Int {
        var x = abs(a)
        var y = abs(b)
        while (y != 0) {
            val t = x % y
            x = y
            y = t
        }
        return maxOf(1, x)
    }

    fun reduced(p: Int, q: Int): Pair<Int, Int> {
        if (q == 0) return p to q
        val g = gcd(p, q)
        var P = p / g
        var Q = q / g
        if (Q < 0) {
            P = -P
            Q = -Q
        }
        return P to Q
    }

    fun canonicalPQUnit(p: Int, q: Int): Pair<Int, Int> {
        if (p <= 0 || q <= 0) return reduced(p, q)
        var num = p
        var den = q
        while (num.toDouble() / den.toDouble() >= 2.0) {
            den *= 2
        }
        while (num.toDouble() / den.toDouble() < 1.0) {
            num *= 2
        }
        return reduced(num, den)
    }

    fun centsForRatio(p: Int, q: Int): Double {
        if (p <= 0 || q <= 0) return Double.NaN
        return 1200.0 * log2(p.toDouble() / q.toDouble())
    }

    fun foldToAudible(f: Double, minHz: Double = 20.0, maxHz: Double = 5000.0): Double {
        if (!f.isFinite() || f <= 0.0 || minHz <= 0.0 || maxHz <= minHz) return f
        var x = f
        while (x < minHz) x *= 2.0
        while (x > maxHz) x *= 0.5
        return x
    }

    fun centsFromET(freqHz: Double, refHz: Double): Double {
        if (freqHz <= 0.0 || refHz <= 0.0) return Double.NaN
        val cents = 1200.0 * log2(freqHz / refHz)
        val nearest = round(cents / 100.0) * 100.0
        var delta = cents - nearest
        if (delta <= -50.0) delta += 100.0
        if (delta > 50.0) delta -= 100.0
        return delta
    }

    fun nearestETSemiIndex(freqHz: Double, refHz: Double): Int {
        if (freqHz <= 0.0 || refHz <= 0.0) return Int.MIN_VALUE
        return round(12.0 * log2(freqHz / refHz)).toInt()
    }

    fun tenneyHeight(p: Int, q: Int): Int {
        val (P, Q) = reduced(p, q)
        return maxOf(abs(P), abs(Q))
    }

    fun unitLabel(p: Int, q: Int): String {
        val (P, Q) = canonicalPQUnit(p, q)
        return "$P/$Q"
    }
}
