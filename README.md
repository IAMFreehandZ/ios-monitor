# iOS Monitor

Native, JIT-free system monitor for a personal, sideloaded iPhone. Monitor device CPU, occupied RAM estimate, per-interface network rates, battery, thermal state and free storage during timed sessions. CPU and RAM also appear in the Lock Screen and Dynamic Island Live Activity. Recent charts retain at most 120 real samples and show breaks for missing readings or sampling gaps.

GitHub Actions builds an unsigned arm64 IPA with its Live Activity extension. Download `iOS-Monitor` from a successful **Build iOS Monitor** workflow run. Sign and install the IPA directly through SideStore or AltStore, keep the `MonitorActivity` extension and register an App ID for each extension. LiveContainer does not register the guest app's Live Activity extension. The bundle IDs are retained from the diagnostic build so a compatible signed update can preserve recordings.

Use **Monitor** to start a 5, 15, 30 or 60 minute session, switch to the app you want to observe, then return and stop. **Sessions** provides past results and exports the existing `metadata.json`, `recording.jsonl` and `summary.json` files. Files are also available under **On My iPhone → iOS Monitor → Sessions**. Stopping or expiry stops the background services and ends the Live Activity.

**Settings** saves session length and background modes. Coarse location defaults on, silent mixing audio defaults off. Allow the requested location access for sessions in other apps; coordinates are never saved. The location default follows the user's successful iPhone 17 Pro Max / iOS 27 comparison. Audio remains an optional backup. With both modes off, sampling is intended for foreground use. Diagnostic events, app overhead and Freeze Collector are available under Settings → Diagnostics.

RAM is a capacity-minus-free-pages estimate, including memory iOS can reclaim. Network rates belong to individual interfaces; they are not summed because VPN and physical interfaces can represent the same traffic. GPU, Neural Engine and device disk throughput are not exposed by this app. Storage shows capacity, not throughput.

Simulator tests verify navigation, settings persistence, real sample advancement, Stop and saved sessions. They cannot qualify background Live Activity presentation or physical-device counter accuracy. The earlier phone tests support the background configuration; battery cost, longer sessions and overhead need further device measurement. See [the test specification](docs/testing/TEST_SPEC.md) and [run template](docs/testing/RUN_TEMPLATE.md).

CI uses macOS 15, Xcode 26.3, and checksum-verified XcodeGen 2.46.0. Run `swift test` for the portable core and `python3 -m unittest discover -s scripts -p 'test_validate_ipa.py' -v` for package validation tests.
