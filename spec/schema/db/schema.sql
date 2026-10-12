-- schema.sql: the CURRENT full schema = all migrations applied in order (checked structurally by make validate-spec).
-- Edit a new migration first, then mirror the change here (new columns go at the end of their table). Header of the first migration follows.

-- Canonical SQLite DDL implemented by GRDB (iOS) and Room (Android). Rules (ADR-0003, ADR-0015):
--   * TEXT lowercase UUID primary keys declared NOT NULL ON CONFLICT REPLACE (SQLiteData sync requirement);
--   * no UNIQUE constraints other than primary keys (sync-safe);
--   * CHECK only for invariants that can never change (booleans, non-negative amounts). Value lists (enums) are
--     enforced in app code and the JSON Schemas: a newer app version's values must still insert on older synced
--     devices, and SQLite cannot change a CHECK without rebuilding the table (forbidden by the sync rules);
--   * every foreign key declares ON DELETE; money = *_minor INTEGER; decimals = TEXT; dates = TEXT YYYY-MM-DD;
--   * timestamps = INTEGER epoch ms UTC; JSON documents = TEXT; booleans = INTEGER 0/1;
--   * after 1.0 ships, migrations only ADD tables or nullable/defaulted columns.
-- Tables marked "local" are never synced or backed up.

CREATE TABLE business (
  id                      TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  name                    TEXT NOT NULL,
  legal_name              TEXT,
  address                 TEXT,                                   -- JSON Address
  email                   TEXT,
  phone                   TEXT,
  website                 TEXT,
  country_code            TEXT NOT NULL,
  tax_config              TEXT NOT NULL,  -- one of: IN, GB, GENERIC (enforced in app code)
  tax_registration        TEXT NOT NULL,
  tax_id                  TEXT,
  extra_ids               TEXT,                                   -- JSON {pan, companyNumber, registeredOffice, lutReference, lutValidUntil}
  home_currency           TEXT NOT NULL,
  turnover_minor          INTEGER CHECK (turnover_minor IS NULL OR turnover_minor >= 0),
  bank                    TEXT,                                   -- JSON bank details
  upi_vpa                 TEXT,
  payment_terms_days      INTEGER NOT NULL DEFAULT 15 CHECK (payment_terms_days >= 0),
  default_notes           TEXT,
  default_terms           TEXT,
  template_id             TEXT NOT NULL DEFAULT 'modern',  -- one of: classic, modern, minimal, compact (enforced in app code)
  accent_color            TEXT,
  logo_asset_id           TEXT,                                   -- soft reference to asset.id
  signature_asset_id      TEXT,                                   -- soft reference to asset.id
  reminder_days_after_due INTEGER,
  custom_rates            TEXT,                                   -- JSON array, GENERIC only
  created_at              INTEGER NOT NULL,
  updated_at              INTEGER NOT NULL,
  deleted_at              INTEGER
);

CREATE TABLE asset (
  id          TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,  -- one of: logo, signature (enforced in app code)
  mime        TEXT NOT NULL,  -- one of: image/png, image/jpeg (enforced in app code)
  sha256      TEXT NOT NULL,
  data        BLOB NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER
);

CREATE TABLE client (
  id               TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id      TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  contact_name     TEXT,
  email            TEXT,
  phone            TEXT,
  billing_address  TEXT,                                          -- JSON Address
  shipping_address TEXT,                                          -- JSON Address
  country_code     TEXT NOT NULL,
  region_code      TEXT,
  tax_id           TEXT,
  is_business      INTEGER NOT NULL DEFAULT 0 CHECK (is_business IN (0, 1)),
  default_currency TEXT,
  notes            TEXT,
  archived_at      INTEGER,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  deleted_at       INTEGER
);

CREATE TABLE catalog_item (
  id                 TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id        TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  description        TEXT,
  kind               TEXT NOT NULL,  -- one of: goods, service (enforced in app code)
  unit               TEXT NOT NULL,
  unit_price_minor   INTEGER NOT NULL CHECK (unit_price_minor >= 0),
  currency           TEXT NOT NULL,
  rate_id            TEXT NOT NULL,
  product_code       TEXT,
  price_includes_tax INTEGER NOT NULL DEFAULT 0 CHECK (price_includes_tax IN (0, 1)),
  archived_at        INTEGER,
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL,
  deleted_at         INTEGER
);

CREATE TABLE numbering_series (
  id              TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id     TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  doc_type        TEXT NOT NULL,  -- one of: invoice, quote (enforced in app code)
  label           TEXT NOT NULL,
  pattern         TEXT NOT NULL,
  reset           TEXT NOT NULL,  -- one of: never, fiscalYear, calendarYear (enforced in app code)
  owner_device_id TEXT NOT NULL,                                  -- only this device advances counters
  counters        TEXT NOT NULL DEFAULT '{}',                     -- JSON {periodKey: nextSeq}
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  deleted_at      INTEGER
);

CREATE TABLE document (
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

CREATE TABLE line_item (
  id               TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  document_id      TEXT NOT NULL REFERENCES document (id) ON DELETE CASCADE,
  position         INTEGER NOT NULL,
  catalog_item_id  TEXT REFERENCES catalog_item (id) ON DELETE SET NULL,
  description      TEXT NOT NULL,
  product_code     TEXT,
  unit             TEXT,
  quantity         TEXT NOT NULL,
  unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0),
  discount         TEXT,                                          -- JSON Discount
  rate_id          TEXT NOT NULL,
  rate_snapshot    TEXT,                                          -- JSON {percent, category, label}
  amount_minor     INTEGER,
  taxable_minor    INTEGER,
  tax_minor        INTEGER,
  total_minor      INTEGER,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  deleted_at       INTEGER
);

CREATE TABLE tax_line (
  id            TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  document_id   TEXT NOT NULL REFERENCES document (id) ON DELETE CASCADE,
  line_id       TEXT REFERENCES line_item (id) ON DELETE CASCADE,  -- NULL = document-level group
  component     TEXT,                                             -- NULL for exempt/nil/outside-scope groups
  rate          TEXT NOT NULL,
  category      TEXT NOT NULL,
  taxable_minor INTEGER NOT NULL,
  tax_minor     INTEGER NOT NULL,
  charged       INTEGER NOT NULL DEFAULT 1 CHECK (charged IN (0, 1)),
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted_at    INTEGER
);

CREATE TABLE payment (
  id           TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
  business_id  TEXT NOT NULL REFERENCES business (id) ON DELETE CASCADE,
  document_id  TEXT NOT NULL REFERENCES document (id) ON DELETE CASCADE,
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  date         TEXT NOT NULL,
  method       TEXT NOT NULL,  -- one of: cash, bank, upi, card, cheque, other (enforced in app code)
  reference    TEXT,
  note         TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER
);

-- local: this device only (never synced, never backed up)
CREATE TABLE device_state (
  id                  TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,                  -- this device's id (owner_device_id)
  device_name         TEXT NOT NULL,
  free_counter_mirror INTEGER NOT NULL DEFAULT 0,
  preferences         TEXT NOT NULL DEFAULT '{}',                 -- JSON
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);

-- local: key/value app state (entitlement cache, last backup time, …)
CREATE TABLE app_state (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);

CREATE INDEX idx_asset_business ON asset (business_id);
CREATE INDEX idx_client_business ON client (business_id, name);
CREATE INDEX idx_catalog_item_business ON catalog_item (business_id, name);
CREATE INDEX idx_numbering_series_business ON numbering_series (business_id, doc_type);
CREATE INDEX idx_document_list ON document (business_id, doc_type, lifecycle, issue_date);
CREATE INDEX idx_document_client ON document (client_id);
CREATE INDEX idx_document_number ON document (business_id, number);
CREATE INDEX idx_line_item_document ON line_item (document_id, position);
CREATE INDEX idx_tax_line_document ON tax_line (document_id);
CREATE INDEX idx_payment_document ON payment (document_id);
