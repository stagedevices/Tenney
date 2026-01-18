package com.tenney.formats

import kotlin.math.abs
import kotlin.math.log2

data class ScalaScale(
    val description: String,
    val entries: List<Entry>
) {
    sealed class Entry {
        data class Ratio(val ratio: Rational) : Entry()
        data class Cents(val value: Double) : Entry()
    }

    data class Rational(val n: Int, val d: Int) {
        init {
            require(d != 0) { "Denominator cannot be zero" }
        }

        val cents: Double = 1200.0 * log2(n.toDouble() / d.toDouble())

        companion object {
            fun of(n: Int, d: Int): Rational {
                if (d == 0) return Rational(1, 1)
                var nn = n
                var dd = d
                if (dd < 0) {
                    nn = -nn
                    dd = -dd
                }
                val g = gcd(nn, dd)
                return Rational(nn / g, dd / g)
            }

            private fun gcd(a: Int, b: Int): Int {
                var x = abs(a)
                var y = abs(b)
                while (y != 0) {
                    val t = x % y
                    x = y
                    y = t
                }
                return maxOf(1, x)
            }
        }
    }

    companion object {
        fun parse(text: String): ScalaScale {
            var lines = text.split(Regex("\\R")).map { it.trim() }
            lines = lines.filter { it.isNotEmpty() && !it.startsWith("!") }
            require(lines.isNotEmpty()) { "Empty .scl" }
            val description = lines.first()
            lines = lines.drop(1)
            require(lines.isNotEmpty()) { "Missing count line" }
            val countLine = lines.first()
            val countToken = Regex("-?\\d+").find(countLine)?.value
                ?: error("Invalid count line")
            val count = countToken.toInt()
            lines = lines.drop(1)

            val entries = mutableListOf<Entry>()
            for (line in lines) {
                if (entries.size >= count) break
                val token = line.split(Regex("\\s+")).firstOrNull().orEmpty()
                if (token.contains("/")) {
                    val parts = token.split("/")
                    val n = parts.getOrNull(0)?.toIntOrNull()
                    val d = parts.getOrNull(1)?.toIntOrNull()
                    if (n != null && d != null && d != 0) {
                        entries.add(Entry.Ratio(Rational.of(n, d)))
                    } else {
                        token.toDoubleOrNull()?.let { entries.add(Entry.Cents(it)) }
                    }
                } else {
                    token.toDoubleOrNull()?.let { entries.add(Entry.Cents(it)) }
                }
            }

            return ScalaScale(description = description, entries = entries)
        }
    }

    fun serialize(): String {
        val out = mutableListOf<String>()
        out.add("! $description")
        out.add(entries.size.toString())
        out.add("!")
        entries.forEach { entry ->
            when (entry) {
                is Entry.Ratio -> out.add("${entry.ratio.n}/${entry.ratio.d}")
                is Entry.Cents -> out.add(String.format("%.5f", entry.value))
            }
        }
        return out.joinToString("\n")
    }
}
