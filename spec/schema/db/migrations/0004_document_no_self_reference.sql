-- 0004_document_no_self_reference: SQLiteData's SyncEngine rejects reference cycles, and document.converted_from_id
-- referenced document itself. The column stays (same name, same values); app code keeps it pointing at a live quote
-- (spec/documents.md §7, §9) — documents are never hard-deleted, so ON DELETE SET NULL never fired anyway.
-- SQLite cannot drop a foreign key in place, so the table is rebuilt (sqlite.org/lang_altertable.html, "Making Other
-- Kinds Of Table Schema Changes"). Runners apply it with foreign-key enforcement off (GRDB's default for migrations;
-- Room: inside a migration with PRAGMA foreign_keys off), so dropping the old table does not cascade to the lines,
-- tax lines and payments that reference it; their REFERENCES document clauses resolve to the new table.

CREATE TABLE document_0004 (
  id                    TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id           TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  doc_type              TEXT NOT NULL,  -- one of: invoice, quote (enforced in app code)
  number                TEXT,                                     -- NULL until issued
  series_id             TEXT REFERENCES numbering_series (id) ON DELETE SET NULL,
  period_key            TEXT,
  lifecycle             TEXT NOT NULL DEFAULT 'draft',  -- one of: draft, issued, void (enforced in app code)
  issue_date            TEXT NOT NULL,
  supply_date           TEXT,
  due_date              TEXT,
  valid_until           TEXT,
  sent_at               INTEGER,
  voided_at             INTEGER,
  void_reason           TEXT,
  quote_outcome         TEXT,  -- one of: accepted, declined, converted (enforced in app code)
  converted_from_id     TEXT,  -- the quote this invoice came from; not a foreign key (0004: SyncEngine rejects self-references)
  currency              TEXT NOT NULL,
  exchange_rate         TEXT,
  supply_type           TEXT NOT NULL,
  place_of_supply       TEXT,
  reverse_charge        INTEGER NOT NULL DEFAULT 0 CHECK (reverse_charge IN (0, 1)),
  prices_include_tax    INTEGER NOT NULL DEFAULT 0 CHECK (prices_include_tax IN (0, 1)),
  round_off             INTEGER CHECK (round_off IS NULL OR round_off IN (0, 1)),
  client_id             TEXT REFERENCES client (id) ON DELETE SET NULL,
  seller_snapshot       TEXT,                                     -- JSON, frozen at issue
  buyer_snapshot        TEXT,                                     -- JSON, frozen at issue
  discount              TEXT,                                     -- JSON Discount
  shipping_minor        INTEGER NOT NULL DEFAULT 0 CHECK (shipping_minor >= 0),
  notes                 TEXT,
  terms                 TEXT,
  template_id           TEXT NOT NULL DEFAULT 'modern',
  tax_config_ref        TEXT NOT NULL,
  revision              INTEGER NOT NULL DEFAULT 0,
  subtotal_minor        INTEGER NOT NULL DEFAULT 0,
  discount_minor        INTEGER NOT NULL DEFAULT 0,
  taxable_minor         INTEGER NOT NULL DEFAULT 0,
  tax_minor             INTEGER NOT NULL DEFAULT 0,
  tax_not_charged_minor INTEGER NOT NULL DEFAULT 0,
  round_off_minor       INTEGER NOT NULL DEFAULT 0,
  total_minor           INTEGER NOT NULL DEFAULT 0,
  computed              TEXT,                                     -- JSON ComputedDocument, stored at issue
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL,
  deleted_at            INTEGER,
  sequence              INTEGER CHECK (sequence IS NULL OR sequence >= 1),  -- 0002: allocated at issue
  reminder_days_after_due_override INTEGER CHECK (reminder_days_after_due_override IS NULL OR reminder_days_after_due_override >= 0)  -- 0003: spec/reminders.md §1
);

INSERT INTO document_0004 (id, business_id, doc_type, number, series_id, period_key, lifecycle, issue_date, supply_date, due_date, valid_until, sent_at, voided_at, void_reason, quote_outcome, converted_from_id, currency, exchange_rate, supply_type, place_of_supply, reverse_charge, prices_include_tax, round_off, client_id, seller_snapshot, buyer_snapshot, discount, shipping_minor, notes, terms, template_id, tax_config_ref, revision, subtotal_minor, discount_minor, taxable_minor, tax_minor, tax_not_charged_minor, round_off_minor, total_minor, computed, created_at, updated_at, deleted_at, sequence, reminder_days_after_due_override)
SELECT id, business_id, doc_type, number, series_id, period_key, lifecycle, issue_date, supply_date, due_date, valid_until, sent_at, voided_at, void_reason, quote_outcome, converted_from_id, currency, exchange_rate, supply_type, place_of_supply, reverse_charge, prices_include_tax, round_off, client_id, seller_snapshot, buyer_snapshot, discount, shipping_minor, notes, terms, template_id, tax_config_ref, revision, subtotal_minor, discount_minor, taxable_minor, tax_minor, tax_not_charged_minor, round_off_minor, total_minor, computed, created_at, updated_at, deleted_at, sequence, reminder_days_after_due_override FROM document;

DROP TABLE document;

ALTER TABLE document_0004 RENAME TO document;

CREATE INDEX idx_document_list ON document (business_id, doc_type, lifecycle, issue_date);
CREATE INDEX idx_document_client ON document (client_id);
CREATE INDEX idx_document_number ON document (business_id, number);
