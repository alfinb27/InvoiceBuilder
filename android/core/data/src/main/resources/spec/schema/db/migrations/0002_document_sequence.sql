-- 0002_document_sequence: the sequence number allocated when a document is issued (spec/documents.md §6), so the
-- next number offered in Settings can stay above the highest one already issued (spec/setup.md §6).
-- Additive and nullable (sync-safe): drafts and documents written by older app versions have NULL.

ALTER TABLE document ADD COLUMN sequence INTEGER CHECK (sequence IS NULL OR sequence >= 1);
