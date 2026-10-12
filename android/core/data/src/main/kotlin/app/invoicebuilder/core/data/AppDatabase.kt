package app.invoicebuilder.core.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import app.invoicebuilder.core.domain.support.SpecLoadingError

/**
 * The app's SQLite database (iOS: `AppDatabase` in InvoiceData). The file is created and migrated by the spec's
 * own SQL (`spec/schema/db/migrations`, bundled by `make sync-spec`), exactly as GRDB does on iOS; Room opens it
 * afterwards and checks that its entities match what the SQL built (ADR-0003: one schema, two platforms).
 */
@Database(
    entities = [
        BusinessEntity::class, AssetEntity::class, ClientEntity::class, CatalogItemEntity::class,
        NumberingSeriesEntity::class, DocumentEntity::class, LineItemEntity::class, TaxLineEntity::class,
        PaymentEntity::class, DeviceStateEntity::class, AppStateEntity::class,
    ],
    version = SpecMigrations.VERSION,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun businesses(): BusinessDao
    abstract fun clients(): ClientDao
    abstract fun catalog(): CatalogDao
    abstract fun series(): NumberingSeriesDao
    abstract fun assets(): AssetDao
    abstract fun devices(): DeviceStateDao
    abstract fun appState(): AppStateDao
    abstract fun documents(): DocumentDao
    abstract fun payments(): PaymentDao

    companion object {
        const val FILE_NAME = "invoices.sqlite"

        /** The on-disk database in the app's private files (≈ Application Support on iOS). */
        fun open(context: Context, name: String? = FILE_NAME): AppDatabase {
            val builder = if (name == null) {
                Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            } else {
                Room.databaseBuilder(context, AppDatabase::class.java, name)
            }
            return builder.openHelperFactory(SpecOpenHelperFactory()).build()
        }

        /** An empty in-memory database for tests and previews. */
        fun inMemory(context: Context): AppDatabase = open(context, null)
    }
}

/** The bundled copy of `spec/schema/db/migrations`, one SQL file per version. */
object SpecMigrations {
    /** The highest migration (backups record it as `dbSchemaVersion`); must equal the number of files. */
    const val VERSION = 4

    /** File names in order; resources cannot be listed, so `MigrationTests` checks this against `spec/`. */
    val files = listOf(
        "0001_init.sql", "0002_document_sequence.sql", "0003_reminder_override.sql",
        "0004_document_no_self_reference.sql",
    )

    fun sql(file: String): String {
        val stream = SpecMigrations::class.java.getResourceAsStream("/spec/schema/db/migrations/$file")
            ?: throw SpecLoadingError("schema/db/migrations/$file", "not bundled; run `make sync-spec`")
        return stream.bufferedReader().use { it.readText() }
    }

    /** Runs migrations `from + 1 … to` (1-based), each file's statements in order. */
    fun migrate(db: SupportSQLiteDatabase, from: Int, to: Int) {
        for (version in (from + 1)..to) {
            for (statement in statements(sql(files[version - 1]))) db.execSQL(statement)
        }
    }

    /** Splits a SQL file into statements (comments dropped; no `;` appears inside our string literals). */
    fun statements(sql: String): List<String> = sql.lines()
        .map { line -> line.substringBefore("--") }
        .joinToString("\n")
        .split(';')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
}

/**
 * Wraps the framework open helper so that creating and upgrading run the spec's SQL instead of Room's generated
 * DDL. Foreign keys are off while migrating (a table rebuild must not cascade, `0004`) and checked afterwards,
 * then switched on for normal use — GRDB's `foreignKeyChecks: .deferred` on iOS.
 */
class SpecOpenHelperFactory(
    private val delegate: SupportSQLiteOpenHelper.Factory = FrameworkSQLiteOpenHelperFactory(),
) : SupportSQLiteOpenHelper.Factory {
    override fun create(configuration: SupportSQLiteOpenHelper.Configuration): SupportSQLiteOpenHelper {
        val room = configuration.callback
        val callback = object : SupportSQLiteOpenHelper.Callback(room.version) {
            override fun onConfigure(db: SupportSQLiteDatabase) {
                db.setForeignKeyConstraintsEnabled(false)
                room.onConfigure(db)
            }

            override fun onCreate(db: SupportSQLiteDatabase) {
                SpecMigrations.migrate(db, 0, version)
                checkForeignKeys(db)
            }

            override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                SpecMigrations.migrate(db, oldVersion, newVersion)
                checkForeignKeys(db)
                // The entities changed with the schema: let Room validate them again and record the new hash.
                db.execSQL("DROP TABLE IF EXISTS room_master_table")
            }

            override fun onDowngrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                throw IllegalStateException("database version $oldVersion is newer than this app ($newVersion)")
            }

            override fun onOpen(db: SupportSQLiteDatabase) {
                room.onOpen(db)
                db.execSQL("PRAGMA foreign_keys = ON")
            }
        }
        return delegate.create(
            SupportSQLiteOpenHelper.Configuration.builder(configuration.context)
                .name(configuration.name)
                .callback(callback)
                .noBackupDirectory(configuration.useNoBackupDirectory)
                .allowDataLossOnRecovery(configuration.allowDataLossOnRecovery)
                .build(),
        )
    }

    private fun checkForeignKeys(db: SupportSQLiteDatabase) {
        db.query("PRAGMA foreign_key_check").use { cursor ->
            if (cursor.moveToFirst()) throw IllegalStateException("foreign key violation in ${cursor.getString(0)} after migrating")
        }
    }
}
