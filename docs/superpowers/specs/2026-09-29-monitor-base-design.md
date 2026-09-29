# iOS Monitor base

Build on `tests/test-spec` for a personal, sideloaded, JIT-free iPhone app. Retain the tested device collectors, session evidence and Live Activity extension, with the existing bundle IDs so installation can preserve recordings.

The Monitor tab shows device CPU, occupied RAM estimate, short trends, per-interface network rates, battery, thermal state and storage capacity. A timed session starts and stops recording and its Live Activity. Unsupported GPU, Neural Engine and device disk throughput entries are removed. Missing readings from a supported collector remain visibly missing.

Sessions provides past recordings, duration, sample coverage and export of the existing three files. Settings persists session duration and background modes. Coarse location is enabled by default; silent mixing audio is an optional backup, off by default. Coordinates are never retained. Denied permission or foreground-only settings must be visible. Diagnostic events and Freeze Collector remain available under Settings for debugging.

Trends retain at most 120 real samples, preserve valid zero, and break at missing readings or sampling gaps. They reset at each new session. No catch-up samples are fabricated. Existing stopped and interrupted recordings remain readable.

GitHub Actions runs core tests, package validation, a simulator UI smoke test, and an unsigned arm64 app/extension build. Deliver its IPA and open a PR to `main`; do not merge. Phone evidence supports the location default, but simulator tests cannot qualify background delivery, battery cost or counter accuracy.
