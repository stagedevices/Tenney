package com.tenney.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.intOrNull
import kotlin.math.max

@Serializable(with = RatioRefSerializer::class)
data class RatioRef internal constructor(
    val p: Int,
    val q: Int,
    val octave: Int = 0,
    val monzo: Map<Int, Int> = emptyMap()
) {
    companion object {
        fun of(p: Int, q: Int, octave: Int = 0, monzo: Map<Int, Int> = emptyMap()): RatioRef {
            return RatioRef(max(1, p), max(1, q), octave, monzo)
        }
    }
}

object RatioRefSerializer : KSerializer<RatioRef> {
    override val descriptor = buildClassSerialDescriptor("RatioRef")

    override fun deserialize(decoder: Decoder): RatioRef {
        val input = decoder as? JsonDecoder
            ?: error("RatioRefSerializer only supports JSON")
        val obj = input.decodeJsonElement() as? JsonObject
            ?: error("RatioRef must be a JSON object")
        val p = (obj["p"] as? JsonPrimitive)?.intOrNull ?: 1
        val q = (obj["q"] as? JsonPrimitive)?.intOrNull ?: 1
        val octave = (obj["octave"] as? JsonPrimitive)?.intOrNull ?: 0
        val monzo = obj["monzo"]?.let {
            input.json.decodeFromJsonElement(mapSerializer, it)
        } ?: emptyMap()
        return RatioRef.of(p = p, q = q, octave = octave, monzo = monzo)
    }

    override fun serialize(encoder: Encoder, value: RatioRef) {
        val output = encoder as? JsonEncoder
            ?: error("RatioRefSerializer only supports JSON")
        val obj = JsonObject(
            mapOf(
                "p" to JsonPrimitive(value.p),
                "q" to JsonPrimitive(value.q),
                "octave" to JsonPrimitive(value.octave),
                "monzo" to output.json.encodeToJsonElement(mapSerializer, value.monzo)
            )
        )
        output.encodeJsonElement(obj)
    }

    private val mapSerializer = MapSerializer(Int.serializer(), Int.serializer())
}
