-- 0003_reminder_override: per-invoice override of business.reminder_days_after_due (spec/reminders.md §1).
-- Additive and nullable (sync-safe): documents written by older app versions have NULL, which defers to the
-- business default.

ALTER TABLE document ADD COLUMN reminder_days_after_due_override INTEGER
  CHECK (reminder_days_after_due_override IS NULL OR reminder_days_after_due_override >= 0);
