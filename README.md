# TerraBot Field

Android field app for PT Alpha Konstruksi Nusantara: **crew attendance** and
the **bored-pile casting log**. Offline-first — usable all day on a site with
no signal; everything recorded is pushed automatically once a signal appears.

Backend: TerraBot (`Terra Nusa Teknologi Office Backend`), routes `/field/*`.
Full design: project doc `claude/RANCANGAN-TERRABOT-FIELD-2026-10-07.md`.

Start with [SETUP.md](SETUP.md).

## Layout

    lib/
      main.dart, app.dart, router.dart
      core/
        db/          drift: MasterRecords (server data), Documents (send queue), Photos, LocalMeta
        network/     Dio client + cross-isolate token refresh
        sync/        sync engine (push → photos → pull) + WorkManager
        device/      location, camera + face count, monotonic timestamp, notifications
        session/     tokens, user, permission map
        theme/, widgets/   colour tokens & components mirrored from TerraBot web
        providers.dart     Riverpod providers
      features/
        login/ home/ attendance/ workers/ casting/ queue/ settings/
        casting/calc/   volume, casting state, tremie cut plan (pure, unit-tested)
    packages/monotonic_clock/   Android plugin: elapsedRealtime + BOOT_COUNT
    test/

## Principles

* The phone generates uuids; saving bumps the version; the queue is
  `version > syncedVersion`.
* A document body is EXACTLY the server schema (`extra="forbid"`). Never add
  local-only fields to it.
* The server decides: distance, trusted time, cheat flags, casting numbers.
  Numbers on the phone are for banners only.
* Explanations go in a `TerraBanner`, not in small helper text under a field.
* Code (names, comments) is English; text shown on screen is Indonesian.
