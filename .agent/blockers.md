# Blockers and discovered defects

## 2026-09-24 — `sync_history` missing `plays_synced`/`skips_synced` on fresh installs (found in Phase 3)

**Symptom (observed on emulator-5554 during Phase 3 verification):** every sync
fails to write a history row:

```
E SQLiteDatabase: android.database.sqlite.SQLiteException:
table sync_history has no column named skips_synced (code 1 SQLITE_ERROR):
... INSERT INTO sync_history(...,skips_synced,...,plays_synced,...) ...
  at dev.educoder.owntone_sync.DatabaseHelper.insertSyncHistory(DatabaseHelper.kt:167)
  at dev.educoder.owntone_sync.BackgroundSyncWorker$doWork$2(BackgroundSyncWorker.kt:678)
```

The event upload itself succeeds (the error is caught; the worker reports
SUCCESS and the events are uploaded). But no `sync_history` row is written, so
the History screen shows nothing and `plays_synced`/`skips_synced` can never be
read back.

**Root cause:** the Dart schema is inconsistent between fresh installs and
upgrades.

- `lib/data/database/database_helper.dart` `_createDB` (fresh installs,
  version 5) creates `sync_history` **without** `plays_synced` /
  `skips_synced`.
- The `oldVersion < 3` migration adds those two columns, but it only runs for
  DBs that pre-date v3.
- The Kotlin worker (`android/.../DatabaseHelper.kt:161-162`) opens the same
  `owntone_sync.db` and, since Phase 0.5 made `playsSynced`/`skipsSynced`
  unconditional (always non-null), always includes both columns in the INSERT.

So on any fresh install the INSERT always fails. Before Phase 0.5 the columns
were included only when the (then-removable) event-tracking toggle was on,
which is why the defect stayed latent.

**Why this is not fixed in Phase 3:** Phase 3's go/no-go is the play/skip
counts on the OwnTone server, and those verified correct. Fixing this means a
schema change to `database_helper.dart` (add the columns to `_createDB` plus a
version-6 migration that must not double-add columns on v3-migrated DBs) — the
disposition table assigns `database_history`/`database_helper.dart` revisions
to Phase 7, and the binding constraints say not to modify the sync pipeline
beyond the named additive changes.

**Affected checks:** Phase 0.5's deferred half-verification ("newest
sync_history row has non-null plays_synced") and spec §7 step 12 / story D3
(History shows plays and skips uploaded per sync run). Phase 7 must fix the
schema before it can verify step 12.

**Not affected:** event recording, event upload, server counts — all verified
working in Phase 3.
