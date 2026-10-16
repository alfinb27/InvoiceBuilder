package app.invoicebuilder.core.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * minSdk 26 means the phone's own SQLite can be as old as 3.18 (Android 8.0), with no JSON functions before
 * Android 14. Room checks queries against a new SQLite at build time and Robolectric runs a new one, so neither
 * notices SQL that an old phone cannot run (issue #28: issuing an invoice failed on Android 8–10). This rejects what
 * SQLite added later, in every Room query and raw statement of `:core:data` and in the spec migrations.
 * `make check-android-sql` goes further and compiles each query on a real SQLite 3.18. (iOS 18 has SQLite 3.43+.)
 */
class SQLiteFloorTests {
    private val newer: Map<String, Regex> = mapOf(
        "upsert, ON CONFLICT … DO (3.24)" to """\bON\s+CONFLICT\b(\s*\([^)]*\))?\s*DO\b""",
        "JSON functions (Android 14)" to """\bjson\w*\s*\(|->""",
        "window functions (3.25)" to """\bOVER\s*\(""",
        "RETURNING (3.35)" to """\bRETURNING\b""",
        "NULLS FIRST / LAST (3.30)" to """\bNULLS\s+(FIRST|LAST)\b""",
        "aggregate FILTER (3.30)" to """\bFILTER\s*\(\s*WHERE\b""",
        "iif() (3.32)" to """\bIIF\s*\(""",
        "ALTER TABLE … COLUMN (3.25, 3.35)" to """\b(DROP|RENAME)\s+COLUMN\b""",
        "STRICT tables (3.37)" to """\bSTRICT\b""",
        "generated columns (3.31)" to """\bGENERATED\s+ALWAYS\b""",
        "RIGHT / FULL JOIN (3.39)" to """\b(RIGHT|FULL)\s+(OUTER\s+)?JOIN\b""",
        "IS DISTINCT FROM (3.39)" to """\bIS\s+(NOT\s+)?DISTINCT\s+FROM\b""",
        "TRUE / FALSE literals (3.23)" to """\b(TRUE|FALSE)\b""",
        "MATERIALIZED (3.35)" to """\bAS\s+(NOT\s+)?MATERIALIZED\b""",
        "newer functions" to
            """\b(unixepoch|concat|concat_ws|string_agg|format|octet_length|timediff|acos|asin|atan2?|ceil|ceiling|cos|degrees|exp|floor|ln|log|log10|log2|mod|pi|pow|power|radians|sin|sqrt|tan|trunc)\s*\(""",
    ).mapValues { Regex(it.value, RegexOption.IGNORE_CASE) }

    private val specRoot = File(System.getProperty("spec.root"))

    /** The SQL in `@Query(…)`, `execSQL(…)` and `query(…)` string arguments, with the file each came from. */
    private fun kotlinStatements(): List<Pair<String, String>> {
        val triple = "\"\"\""
        val call = Regex("""(?:@Query|execSQL|\.query)\(\s*(?:$triple(.*?)$triple|"((?:[^"\\]|\\.)*)")""", RegexOption.DOT_MATCHES_ALL)
        val sources = specRoot.resolve("../android/core/data/src/main/kotlin").walkTopDown().filter { it.extension == "kt" }
        return sources.flatMap { file ->
            call.findAll(file.readText()).map { file.name to (it.groupValues[1].ifEmpty { it.groupValues[2] }) }
        }.toList()
    }

    private fun migrationStatements(): List<Pair<String, String>> =
        specRoot.resolve("schema/db/migrations").listFiles()!!.filter { it.extension == "sql" }.map { file ->
            file.name to file.readLines().joinToString("\n") { it.substringBefore("--") }
        }

    private fun violations(statements: List<Pair<String, String>>): List<String> = statements.flatMap { (file, sql) ->
        // Quoted text is data, not syntax ('$.name' in a LIKE pattern, a default value).
        val code = sql.replace(Regex("'(?:[^']|'')*'"), "''")
        newer.filter { (_, pattern) -> pattern.containsMatchIn(code) }.keys.map { "$file: $it in: ${sql.trim().replace(Regex("\\s+"), " ").take(140)}" }
    }

    @Test fun theDataLayerOnlyUsesSQLThatAndroid8CanRun() {
        val statements = kotlinStatements()
        assertTrue("found only ${statements.size} statements: the scan is broken", statements.size > 50)
        assertEquals(emptyList<String>(), violations(statements))
    }

    @Test fun theSpecMigrationsRunOnAndroid8() {
        val statements = migrationStatements()
        assertTrue(statements.isNotEmpty())
        assertEquals(emptyList<String>(), violations(statements))
    }

    @Test fun theCheckCatchesWhatWouldBreak() {
        val bad = listOf(
            "t" to "INSERT INTO app_state (`key`, value) VALUES (:key, :value) ON CONFLICT(`key`) DO UPDATE SET value = excluded.value",
            "t" to "SELECT json_extract(seller_snapshot, '$.logoAssetId') FROM document",
            "t" to "SELECT SUM(total_minor) OVER (PARTITION BY client_id) FROM document",
        )
        assertEquals(3, violations(bad).size)
        // The old column-constraint form stays allowed: every synced table's key uses it.
        assertEquals(emptyList<String>(), violations(listOf("t" to "CREATE TABLE x (id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE)")))
    }
}
