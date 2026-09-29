# iOS Monitor Diagnostics

Native, JIT-free diagnostic app for a sideloaded iPhone system monitor. It tests device CPU/RAM counter access, per-interface network rates, background sampling with silent mixing audio or optional coarse location, and Live Activity freshness. GPU, Neural Engine, and device disk throughput are explicitly unavailable in this build.

GitHub Actions builds an unsigned arm64 IPA with its Live Activity extension. Download `iOS-Monitor-Diagnostics` from a successful **Diagnostic IPA** workflow run. Sign and install the IPA through SideStore or AltStore and keep the extension when prompted.

Start a session, use another app, return and Stop. Saved sessions include an exportable JSONL recording, metadata and a JSON continuity summary. Files are also available under **On My iPhone → Monitor Diagnostics → Sessions**. Freeze Collector intentionally stops real samples so stale Live Activity behavior can be observed.

The initial build establishes feasibility. A successful CI build is not proof of physical device counter access, background reliability or measurement accuracy. See [the test specification](docs/testing/TEST_SPEC.md) and [run template](docs/testing/RUN_TEMPLATE.md) for qualification.

CI uses macOS 15, Xcode 26.3, and checksum-verified XcodeGen 2.46.0. Run `swift test` for the portable core and `python3 -m unittest discover -s scripts -p 'test_validate_ipa.py' -v` for package validation tests.
