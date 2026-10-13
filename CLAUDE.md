# CLAUDE.md — TerraBot Field (Flutter)

Code language: English — file, class, method and variable names and comments.

Text shown on screen is TRANSLATED: Indonesian (default), English and 中文.
Never hard-code a user-visible string. Add the key to all three of
`lib/l10n/app_id.arb`, `app_en.arb`, `app_zh.arb` (Indonesian carries the
`@key` description), run `flutter gen-l10n`, and read it with
`t(context).theKey` (`lib/core/i18n.dart`). The synthetic
`package:flutter_gen` is GONE since Flutter 3.47 — the generated classes
live in `lib/l10n/`.

What stays untranslated on purpose: server contract values (photo kinds,
review statuses, reason codes), stored ids (`accentOptions.id`), and field
terms that are the same on every site in all three languages (TM, slump,
tremie, cut-off) — those keep their trade spelling per language.

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

## Release

Any change under `lib/` or `android/` that will reach a phone means a new
build, and a new build means a new `versionCode`. **Bump `version:` in
`pubspec.yaml` as part of the change itself** — do not finish the work and
then ask whether to bump it.

    version: 1.0.0+5     # the number after + always goes up, never reused

Play rejects a `versionCode` that has been uploaded before, and the number
cannot be recycled even if the release was discarded. Finding that out at
the upload screen wastes a whole build.

Raise the number after `+` for an ordinary release. Raise the semantic part
(`1.0.1`) when the release must be forcible: `urai_versi()` on the server
drops everything after `+`, so `1.0.0+4` and `1.0.0+5` are the SAME version
to `FIELD_MIN_APP_VERSION` and cannot be told apart.
