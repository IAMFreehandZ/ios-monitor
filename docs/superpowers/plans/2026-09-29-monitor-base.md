# iOS Monitor base implementation

**Goal:** Deliver a usable monitor app, an unsigned IPA and a PR from `tests/test-spec` to `main`.
**Architecture:** Preserve the collector / recorder / serialized ActivityKit publisher. Add a small portable preferences and trend model; compose SwiftUI screens around the existing session controller.
**Tech stack:** Swift 5, SwiftUI, ActivityKit, XCTest, Python package validation, XcodeGen, GitHub Actions macOS.
**Spec:** `docs/superpowers/specs/2026-09-29-monitor-base-design.md`.
**Global constraints:** Same bundle IDs and recording format; JIT-free; only observed samples; no unavailable hardware placeholders; user has authorized current branch work, build and PR.
**Review focus:** Stop and expiry, permission changes, stale readings, persisted settings, bounded memory, old recordings, extension packaging.

## Task 1: Preferences and trends

**Consumes:** Existing telemetry types and Swift package.
**Produces:** `MonitorPreferences`, `TrendHistory` and behavioral core tests.

- [ ] Write tests for default background choices, settings round trip and invalid input recovery, bounded history, valid zero, missing values and gaps.
- [ ] Run `swift test` on GitHub with minimal compiling scaffolds. Expected: new assertions fail for the missing behavior; existing tests pass.
- [ ] Implement preferences decoding and bounded history. Expected next CI: all core tests pass.

## Task 2: Native application

**Consumes:** Task 1 types and existing session/recording services.
**Produces:** Monitor, Sessions and Settings screens; persistent controller configuration; session metadata in history; simulator smoke test.

- [ ] Add UI smoke test for start, advancing sample count, stop, exportable session, settings persistence and a second session.
- [ ] Run the smoke test against the diagnostic UI before replacing it. Expected: missing new navigation/control identifiers fail.
- [ ] Implement dashboard with bounded trends, timed controls and honest permission/activity status; move diagnostics into Settings; remove permanent unsupported metric entries.
- [ ] Add session details/export, persist settings and retain old session decoding; update display name, version and Live Activity branding.
- [ ] Build and run UI smoke test. Expected: core/package tests and smoke test pass, app plus extension compile, simulator screenshots are captured.

## Task 3: Delivery and review

**Consumes:** Task 2 app and tests, existing IPA workflow/validator.
**Produces:** Final build artifact, documentation and PR.

- [ ] Update workflow for PR/main builds and named `iOS-Monitor` artifact; publish smoke results and screenshots.
- [ ] Update README with current scope, installation and realistic device qualification limits.
- [ ] Obtain one independent review of the whole branch; fix material findings with failing regression tests followed by the full suite.
- [ ] Verify final GitHub run, download/extract the actual IPA and validate locally.
- [ ] Create and attach the PR, keeping the branch available as the base for later work.
