# CLAUDE.md — TerraBot Field (Flutter)

Code language: English — file, class, method and variable names and comments.
Text shown on screen stays Indonesian (the users are foremen and QS on site).

## Must

- `Documents.body` must be EXACTLY the backend Pydantic model in
  `schemas/field_schema.py` (`DataPekerja`, `DataAbsen`, `DataTandaBor`,
  `DataCor`). The server uses `extra="forbid"`: an extra field = item REJECTED.
- Server contract values stay as the server spells them (photo kinds
  `wajah`/`absen_masuk`/…, review statuses `dikirim`/`ditinjau`/…, reason
  codes). Local-only values are English (send status
  `pending`/`sent`/`deferred`/`rejected`/`failed`).
- Decimals are sent as TEXT (`decimalText`), times as ISO with offset
  (`isoWithOffset`). Never `toIso8601String()` for local times.
- Never write the `MasterRecords` table from a screen — only from a pull.
- Token refresh only through `ApiClient._refresh` (cross-isolate lock).
  Refresh tokens are single-use; two concurrent refreshes revoke the session.
- Build services only through `AppContext.open()` — used by `main()` AND the
  background worker.
- Explanations go in `TerraBanner`; no small helperText.
- Changing a drift table → bump `schemaVersion` + migration, then
  `dart run build_runner build`.

## Test

    flutter analyze
    flutter test

Pure logic (casting numbers, cut plan) in `lib/features/casting/calc/` and
the worker rules in `lib/features/workers/worker.dart` must have tests in
`test/`.

## Workers

Workers belong to the company, not to whoever registered them: every user
pulls every worker and may absent or correct any of them. `projectID` (main
project, optional) and `lastProjectID`/`lastSeenDate` (kept by the server on
every attendance) only group and sort — they never limit where a worker can
be absent. `foremanUserID` on a worker means "registered by".
