package app.invoicebuilder.core.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.math.BigDecimal

/** The repository's `spec/` folder (passed by Gradle), so a fixture change is picked up without a sync step. */
object Spec {
    val root: File = File(System.getProperty("spec.root") ?: error("spec.root is not set; run through Gradle"))
}

/** One golden fixture case (`spec/fixtures/README.md`). The test name is the case id. iOS: `FixtureCase`. */
data class FixtureCase(
    val id: String,
    val kind: String,
    val input: JsonObject,
    val expected: JsonElement,
    /** Tax cases name their config next to `input`. */
    val config: String?,
) {
    fun string(key: String): String = input[key]?.jsonPrimitive?.contentOrNull ?: error("$id: input.$key is missing")
    fun long(key: String): Long = input[key]?.jsonPrimitive?.longOrNull ?: error("$id: input.$key is missing")
    fun optionalString(key: String): String? = (input[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
}

object Fixtures {
    /** Every case in `spec/fixtures (every JSON file)`, in file-name order. */
    val all: List<FixtureCase> by lazy {
        File(Spec.root, "fixtures").walkTopDown().filter { it.isFile && it.extension == "json" }.sortedBy { it.path }
            .flatMap { file ->
                val root = Json.parseToJsonElement(file.readText()).jsonObject
                val kind = root["kind"]!!.jsonPrimitive.content
                root["cases"]!!.jsonArray.map { case ->
                    val fields = case.jsonObject
                    FixtureCase(
                        id = fields["id"]!!.jsonPrimitive.content, kind = kind,
                        input = fields["input"]?.jsonObject ?: JsonObject(emptyMap()),
                        expected = fields["expected"] ?: JsonNull,
                        config = fields["config"]?.jsonPrimitive?.contentOrNull,
                    )
                }
            }.toList()
    }

    fun cases(kind: String): List<FixtureCase> = all.filter { it.kind == kind }
}

/**
 * Subset match (`spec/fixtures/README.md`): every expected key must be present and equal (extra actual keys
 * allowed), arrays compare element by element with equal lengths, and an expected `null` means null or absent.
 */
fun mismatches(expected: JsonElement, actual: JsonElement?, path: String = ""): List<String> = when {
    expected is JsonNull -> if (actual == null || actual is JsonNull) emptyList() else listOf("$path: expected null, got $actual")
    expected is JsonObject && actual is JsonObject ->
        expected.keys.sorted().flatMap { mismatches(expected[it]!!, actual[it], "$path.$it") }
    expected is JsonArray && actual is JsonArray ->
        if (expected.size != actual.size) listOf("$path: expected ${expected.size} items, got ${actual.size}")
        else expected.indices.flatMap { mismatches(expected[it], actual[it], "$path[$it]") }
    expected is JsonPrimitive && actual is JsonPrimitive && primitivesEqual(expected, actual) -> emptyList()
    else -> listOf("${path.ifEmpty { "value" }}: expected $expected, got ${actual ?: "nothing"}")
}

private fun primitivesEqual(expected: JsonPrimitive, actual: JsonPrimitive): Boolean {
    if (expected.isString || actual.isString) return expected.isString == actual.isString && expected.content == actual.content
    expected.booleanOrNull?.let { return it == actual.booleanOrNull }
    val left = expected.content.toBigDecimalOrNull()
    val right = actual.content.toBigDecimalOrNull()
    return left != null && right != null && left.compareTo(right) == 0 || expected.content == actual.content
}

private fun String.toBigDecimalOrNull(): BigDecimal? = runCatching { BigDecimal(this) }.getOrNull()

/** Fails with every difference between [actual] and the fixture's `expected`. */
fun expectFixture(fixture: FixtureCase, actual: JsonElement) {
    val problems = mismatches(fixture.expected, actual)
    if (problems.isNotEmpty()) throw AssertionError("${fixture.id}: ${problems.joinToString("; ")}")
}

fun obj(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.associate { (key, value) -> key to json(value) })

fun json(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is JsonElement -> value
    is String -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is Boolean -> JsonPrimitive(value)
    is List<*> -> JsonArray(value.map(::json))
    is Map<*, *> -> JsonObject(value.entries.associate { (key, item) -> key.toString() to json(item) })
    else -> error("cannot convert $value")
}
