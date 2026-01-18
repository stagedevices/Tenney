package com.tenney.core

import kotlin.text.isBlank
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
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
import java.util.UUID

@Serializable(with = TenneyScaleSerializer::class)
data class TenneyScale internal constructor(
    val id: String,
    val name: String,
    val descriptionText: String,
    val degrees: List<RatioRef>,
    val tags: List<String>,
    val favorite: Boolean,
    val lastPlayed: Double?,
    val referenceHz: Double,
    val rootLabel: String?,
    val periodRatio: Double,
    val detectedLimit: Int,
    val maxTenneyHeight: Int,
    val author: String?
) {
    companion object {
        fun of(
            id: String? = null,
            name: String,
            descriptionText: String = "",
            degrees: List<RatioRef> = emptyList(),
            tags: List<String> = emptyList(),
            favorite: Boolean = false,
            lastPlayed: Double? = null,
            referenceHz: Double = 440.0,
            rootLabel: String? = null,
            periodRatio: Double = 2.0,
            detectedLimit: Int? = null,
            maxTenneyHeight: Int? = null,
            author: String? = null
        ): TenneyScale {
            val limit = detectedLimit ?: TenneyScaleDerived.detectedLimit(degrees)
            val height = maxTenneyHeight ?: TenneyScaleDerived.maxTenneyHeight(degrees)
            return TenneyScale(
                id = id ?: UUID.randomUUID().toString(),
                name = name,
                descriptionText = descriptionText,
                degrees = degrees,
                tags = tags,
                favorite = favorite,
                lastPlayed = lastPlayed,
                referenceHz = referenceHz,
                rootLabel = rootLabel,
                periodRatio = periodRatio,
                detectedLimit = limit,
                maxTenneyHeight = height,
                author = author
            )
        }
    }
}

@Serializable
internal data class TenneyScaleTone(
    val id: String,
    val ref: RatioRef,
    val name: String? = null,
    val isEnabled: Boolean = true
)

object TenneyScaleSerializer : KSerializer<TenneyScale> {
    override val descriptor = buildClassSerialDescriptor("TenneyScale")

    private fun JsonObject.prim(key: String): JsonPrimitive? = this[key] as? JsonPrimitive
    private fun JsonPrimitive.intOrNullCompat(): Int? = this.content.toIntOrNull()
    private fun JsonPrimitive.doubleOrNullCompat(): Double? = this.content.toDoubleOrNull()
    private fun JsonPrimitive.boolOrNullCompat(): Boolean? = when (this.content) {
        "true" -> true
        "false" -> false
        else -> null
    }
    private fun String?.nilIfBlankOrNullLiteral(): String? = this?.let {
        val t = it.trim()
        if (t.isEmpty() || t.equals("null", ignoreCase = true)) null else t
    }

    override fun deserialize(decoder: Decoder): TenneyScale {
        val input = decoder as? JsonDecoder
            ?: error("TenneyScaleSerializer only supports JSON")
        val obj = input.decodeJsonElement() as? JsonObject
            ?: error("TenneyScale must be a JSON object")

        val id = obj.prim("id")?.content.nilIfBlank() ?: UUID.randomUUID().toString()
        val name = obj.prim("name")?.content.nilIfBlank() ?: "Untitled Scale"
        val descriptionText = obj.prim("descriptionText")?.content
            ?: obj.prim("notes")?.content
            ?: ""

        val degrees = when {
            obj.containsKey("degrees") -> {
                input.json.decodeFromJsonElement(ListSerializer(RatioRefSerializer), obj.getValue("degrees"))
            }
            obj.containsKey("tones") -> {
                val tones = input.json.decodeFromJsonElement(
                    ListSerializer(TenneyScaleTone.serializer()),
                    obj.getValue("tones")
                )
               tones.filter { it.isEnabled }.map { it.ref }
            }
            else -> emptyList()
        }

        val tags = obj["tags"]?.let {
            input.json.decodeFromJsonElement(ListSerializer(String.serializer()), it)
        } ?: emptyList()
        val favorite = obj.prim("favorite")?.boolOrNullCompat() ?: false
        val lastPlayed = obj.prim("lastPlayed")?.doubleOrNullCompat()
        val referenceHz = obj.prim("referenceHz")?.doubleOrNullCompat()
            ?: obj.prim("rootHz")?.doubleOrNullCompat()
            ?: 440.0
        val rootLabel = obj.prim("rootLabel")?.content.nilIfBlankOrNullLiteral()
        val periodRatio = obj.prim("periodRatio")?.doubleOrNullCompat() ?: 2.0
        val author = obj.prim("author")?.content.nilIfBlankOrNullLiteral()

        val detectedLimit = obj.prim("detectedLimit")?.intOrNullCompat()
            ?: TenneyScaleDerived.detectedLimit(degrees)
        val maxTenneyHeight = obj.prim("maxTenneyHeight")?.intOrNullCompat()
            ?: TenneyScaleDerived.maxTenneyHeight(degrees)

        return TenneyScale(
            id = id,
            name = name,
            descriptionText = descriptionText,
            degrees = degrees,
            tags = tags,
            favorite = favorite,
            lastPlayed = lastPlayed,
            referenceHz = referenceHz,
            rootLabel = rootLabel,
            periodRatio = periodRatio,
            detectedLimit = detectedLimit,
            maxTenneyHeight = maxTenneyHeight,
            author = author
        )
    }

    override fun serialize(encoder: Encoder, value: TenneyScale) {
        val output = encoder as? JsonEncoder
            ?: error("TenneyScaleSerializer only supports JSON")
        val fields = linkedMapOf<String, kotlinx.serialization.json.JsonElement>()
        fields["id"] = JsonPrimitive(value.id)
        fields["name"] = JsonPrimitive(value.name)
        fields["descriptionText"] = JsonPrimitive(value.descriptionText)
        fields["degrees"] = output.json.encodeToJsonElement(ListSerializer(RatioRefSerializer), value.degrees)
        fields["tags"] = output.json.encodeToJsonElement(ListSerializer(String.serializer()), value.tags)
        fields["favorite"] = JsonPrimitive(value.favorite)
        value.lastPlayed?.let { fields["lastPlayed"] = JsonPrimitive(it) }
        fields["referenceHz"] = JsonPrimitive(value.referenceHz)
        value.rootLabel?.let { fields["rootLabel"] = JsonPrimitive(it) }
        fields["periodRatio"] = JsonPrimitive(value.periodRatio)
        fields["detectedLimit"] = JsonPrimitive(value.detectedLimit)
        fields["maxTenneyHeight"] = JsonPrimitive(value.maxTenneyHeight)
        value.author?.let { fields["author"] = JsonPrimitive(it) }
        val obj = JsonObject(fields)
        output.encodeJsonElement(obj)
    }
}
