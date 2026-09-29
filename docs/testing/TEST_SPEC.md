# iOS Monitor test specification

Date: 2026-09-29  
Status: Core tests and diagnostic builds implemented; physical-device qualification is partial. The monitor base changes the defaults below using the user's background-mode comparison. Case completion must be supported by run evidence.
Repository: [IAMFreehandZ/ios-monitor](https://github.com/IAMFreehandZ/ios-monitor)  
Development branch: `tests/test-spec`  
Primary device: iPhone 17 Pro Max, iOS 27. Record the exact OS build for every device run.

## 1. Purpose and success criteria

The app records iPhone system vitals during short to medium debugging sessions and displays recent measurements in a Live Activity while another app is open. Builds and automated tests run on GitHub Actions because the development environment is Windows. The device app is sideloaded.

Tests establish counter access and actual background sampling for each selected mode. A moving timer or a visible Live Activity is insufficient evidence of execution. Each recording needs distinct sample sequence numbers, timestamps, raw counters, and execution events.

Success means:

1. CPU and RAM measurements come from identified device counters and use verified calculations.
2. Samples continue during ordinary use of another app under the selected background mode.
3. The foreground app's audio and media controls continue to work.
4. The Live Activity makes the age and availability of its measurements clear.
5. Stopping or completing a session releases the background services.
6. A GitHub-built IPA can be signed and installed from Windows with its Live Activity extension intact.

## 2. Proposed v1 contract

These values make the tests concrete. They are proposed product choices and acceptance targets, not guarantees made by iOS. Change them through a reviewed spec revision if device evidence requires it.

| Setting or rule | Proposed value |
| --- | --- |
| Recording durations | 5, 15, 30, and 60 minutes; default 15 minutes; manual Stop available |
| Sampling interval | 1 second, scheduled using a monotonic clock |
| Live Activity submission interval | At most one ordinary update every 2 seconds; terminal updates may be immediate |
| Background audio | Disabled by default; optional independent backup switch |
| Background location | Enabled for an active recording by default; user can disable it |
| Silent audio behavior | Loop silence with an audio session that mixes with other apps |
| Location behavior | Request coarse accuracy, allow background updates, and test automatic-pause prevention |
| Permission behavior | Request location only after its switch is enabled; preserve the user's audio preference if location is refused |
| After app relaunch | Close an unfinished recording as interrupted; a new recording requires Start |
| Stale content | Publish a stale date 5 seconds after the sample timestamp; render an explicit stale state |
| Unsupported readings | Omit GPU, Neural Engine and device disk throughput from the app; failures of supported collectors retain their reason and real zero remains valid |

With both background switches disabled, the app records while execution is available and reports gaps when resumed. That profile makes no persistence promise.

### Metric definitions

| Metric | Definition and scope |
| --- | --- |
| CPU | Device CPU busy tick delta divided by total tick delta, aggregated across reported cores; 0-100%. Include user, system, and nice ticks as busy. This is a time-based utilization reading. |
| RAM | Occupied RAM estimate = physical capacity minus free-page bytes. Label it as an estimate. Show the available VM categories separately; cached or reclaimable memory contributes to this estimate, so it is not a memory-pressure score. |
| Network | Receive/transmit byte deltas divided by actual elapsed seconds, for identified interfaces. The initial view reports per-interface values; it makes no per-app attribution. |
| Battery | Reported charge level and charging state. Unknown readings remain unavailable. |
| Thermal | The reported nominal, fair, serious, or critical state. |
| Storage | Capacity and available space. Actual device disk read/write throughput is a separate capability investigation. |
| GPU / Neural Engine | Capability investigation. Require a working, identified source before displaying utilization; do not derive percentages from thermals or CPU activity. |
| Monitor overhead | The monitor's own CPU time and memory footprint, labeled as app metrics. Own-process CPU uses 100% to mean one fully occupied core. |

CPU and RAM are the core capability gate. Network rates may be retained as unavailable if the phone does not expose suitable counters, with an explicit recorded finding and corresponding product scope revision. GPU, Neural Engine, and disk throughput availability are recorded findings rather than prerequisites for the first diagnostic build.

## 3. Evidence and test environments

### Recording evidence

The diagnostic build must support exporting a session record from the phone to the Windows project, through Files or the sideloading tool's file-sharing support. Machine-readable samples and events use JSON Lines; a compact session summary uses JSON.

Capture:

- App commit/build, toolchain, device model, iOS version/build, and signing method.
- Session ID, recording duration, both background settings, location authorization, Low Power Mode, and audio route.
- Strictly increasing sample sequence numbers, UTC timestamps, monotonic elapsed times, and the actual interval used for each rate.
- Each metric's source, scope, unit, status, raw input, computed value, and any API error.
- Session start/stop, background/foreground transitions, audio interruptions/recovery, route changes, location authorization changes, and collector failures.
- Live Activity update submissions and their completion or failure, with the sample sequence submitted. Submission completion is not evidence that iOS rendered the value.
- Recording gaps and their reasons where known. Missing periods remain missing; do not interpolate them into measured history.

The location fallback's evidence consists of authorization and service events. The recording has no need to retain coordinates. Diagnostic exports should be selective so verbose logging does not dominate the measured workload.

### Execution environments

| Environment | What it can establish |
| --- | --- |
| Automated tests on GitHub macOS | Counter arithmetic, error cases, clocks, session transitions, export integrity, and Live Activity content contracts using fixtures/fakes |
| iPhone simulator on GitHub macOS | App/extension integration, presentation with fixtures, permission/availability simulations, and launch behavior |
| Physical iPhone + Windows | Actual counter access, background persistence, audio coexistence, rendered freshness, location behavior, installation, and overhead |

Simulator CPU or memory readings can describe the host environment. They must not be accepted as proof of iPhone counter access. Record cases as Pass, Fail, Blocked, or Not run; unavailable hardware evidence is never a Pass.

## 4. GitHub build and installation tests

These cases become executable when the diagnostic app and workflow exist.

| ID | Test | Expected result |
| --- | --- | --- |
| CI-01 | Build from a clean checkout on a pinned macOS runner and selected Xcode version. | The app and Live Activity extension compile for a physical iPhone. Logs record runner image, `xcodebuild -version`, SDK, and source commit. |
| CI-02 | Run the automated metric, lifecycle, export, and content suites with fixture providers. | The job fails for a failing assertion or missing required suite. Skipped tests are listed and cannot substitute for the required cases. |
| CI-03 | Inspect the unsigned device IPA before uploading it as an Actions artifact. | `Payload` contains an arm64 device app and its embedded `.appex`; bundle identifiers and required audio/location background declarations are consistent. An unsigned artifact is labeled as requiring signing. |
| CI-04 | Download the artifact on Windows, sign it, and sideload it with the extension preserved. | The app launches on the target phone and can create a Live Activity. Record the signing tool/version and actual app/extension identifiers after signing. |
| CI-05 | Repeat installation after signing renewal or replacing the app with a newer build. | Recording and Live Activities still work. Any expired provisioning profile, removed extension, or identifier mismatch produces a distinct diagnosis. |

## 5. Automated metric tests

Use raw fixtures and exact expected outputs. Calculated ratios use a numeric tolerance of `1e-6`; byte counts and statuses are exact. Test the actual calculator used by the collector.

| ID | Input or fault | Expected result |
| --- | --- | --- |
| MET-01 | CPU previous `(user=100, system=40, nice=10, idle=850)`; current `(130, 60, 10, 900)`. | Busy delta 50, total delta 100, utilization 50%. |
| MET-02 | Two cores report `(busy delta=30, total delta=100)` and `(10, 20)`. | Aggregate utilization is `100 * 40 / 120 = 33.333333%`; aggregate by ticks rather than averaging the two percentages. |
| MET-03 | Received bytes advance from 1,000,000 to 1,500,000 over 2 seconds; repeat over 4 seconds. | Rates are 250,000 and 125,000 B/s. Use actual elapsed time rather than the requested sampling interval. |
| MET-04 | First counter snapshot; unchanged total CPU ticks; duplicate timestamp; or nonpositive elapsed interval. | First snapshot is warming up. Nonadvancing/invalid inputs produce an unavailable/error result with a reason; no division by zero, NaN, infinity, or invented zero reading. |
| MET-05 | A same-epoch 32-bit counter advances from 4,294,967,040 to 256; then test an explicitly changed counter epoch. | Supported modular wrap produces a delta of 512. An epoch change resets the baseline and reports warming up. An unexplained decrease is unavailable rather than a huge inferred transfer. |
| MET-06 | 1,024 free pages with page sizes 4,096 and 16,384 bytes. | Free bytes are 4,194,304 and 16,777,216 respectively. Use the reported page size. |
| MET-07 | RAM capacity 1,073,741,824 bytes; free bytes 16,777,216. | Occupied estimate is 1,056,964,608 bytes, or 0.984375 GiB. Overlapping VM categories are not added to this total. |
| MET-08 | API denied, invalid result length, free RAM greater than capacity, missing interface data, or unsupported counter. | That reading is unavailable/error, retaining its diagnostic reason and scope. Other valid readings continue. |
| MET-09 | Fixtures contain device CPU, own-process CPU, own-process RAM, and a provider labeled as unsupported GPU. | Device and app readings retain their distinct labels. Own-process readings never fill a missing device metric. Unsupported GPU remains unavailable. |
| MET-10 | Interface added, removed, or recreated; VPN/loopback and physical interfaces coexist. | Maintain separate baselines and values for identified interfaces, reset recreated sources, and avoid an aggregate that double counts traffic. Interface discovery does not assume a fixed Wi-Fi name. |
| MET-11 | Battery `-1`, battery `0`, valid idle CPU `0%`, zero-byte traffic, and all thermal states. | Unknown battery is unavailable; real zero values display as zero. Thermal states retain their names and are not converted into temperatures. RAM uses GiB; rates use B/s or decimal kB/s/MB/s with visible units. |

## 6. Automated session, export, and Live Activity tests

Inject clocks, collector results, background-service availability, the recording sink, and ActivityKit responses. Verify observable session behavior rather than private implementation details.

| ID | Scenario | Expected result |
| --- | --- | --- |
| LIF-01 | Start tapped repeatedly or during an in-flight start. | One recording, one sampler, and one set of requested background services. No duplicated sample sequence or Live Activity. |
| LIF-02 | Stop during startup, recording, or audio recovery; repeat Stop. | Stop is idempotent. No later callback restarts recording or background audio. Services are released and the final summary records the stop reason. |
| LIF-03 | Fake monotonic clock crosses the 5-, 15-, 30-, and 60-minute deadlines; repeat with a suspension crossing a deadline. | Recording ends at the selected duration while execution is available; resumption after a deadline stops immediately. No catch-up samples are fabricated. |
| LIF-04 | Change audio/location switches during a session, then deny or revoke location authorization. | Requested modes follow the switches. Location refusal preserves the audio preference and leaves recording behavior and permission state explicit. No location prompt while its switch is off. |
| LIF-05 | Audio interrupted, resumption unavailable, route changed, or media services reset; Stop while recovery is pending. | Recovery is limited to an active recording and permitted audio use. Record gaps and recovery failures. Retry logic does not restart a stopped session or spin without a delay. |
| LIF-06 | Reopen with an unfinished recording and a new launch/clock epoch. | Previous recording is marked interrupted. No automatic restart and no rates calculated between unrelated clock epochs. |
| LIF-07 | Recording sink fails, runs out of space, or returns a partially written last record. | Retain parseable prior records, expose the recording failure, stop the recording and its background services, and keep memory bounded. A truncated final record is identifiable. |
| LIF-08 | Wall clock jumps forward/backward or timezone changes during recording. | Ordering, duration, and rates use monotonic time. UTC timestamps remain available for correlation; the clock change is recorded. |
| LA-01 | Encode/decode a content state containing valid, warming-up, unavailable, and error values. | Round trip preserves values, units, scope, sequence, and sample timestamp. Updated content stays below ActivityKit's 4 KB limit. |
| LA-02 | Last sample is 4.9 seconds old, then reaches 5 seconds. | Freshness policy changes at 5 seconds. The published stale date is based on the sample timestamp, not the time the publisher eventually submitted it. |
| LA-03 | Values remain constant while real samples advance; then collection stops while a UI timer continues. | Real samples advance the sequence and timestamp. A display timer cannot create fresh metric samples or extend stale dates. |
| LA-04 | Live Activities disabled, start rejected, update fails, or the system ends the activity. | Recording remains usable through the app, the presentation failure is explicit, and retries are bounded. User dismissal is recorded without creating a replacement activity automatically. |
| LA-05 | An older update completes after a newer update, or a pending update completes after Stop. | Visible content does not regress to an older sample; terminal state is not replaced by a running state. |

## 7. Physical-device tests

### Common procedure and continuity target

Start the recording in the foreground, note the selected modes, switch to the test app, and return only as the case requires. Export the recording and correlate visible readings with sample sequence numbers. Record a separate result for each variant in a row.

For an ordinary uninterrupted session, the proposed sampling target is:

- At least 99% of the scheduled one-second sampling slots contain a distinct sample attempt.
- P95 interval between attempts is at most 1.5 seconds, with no unexplained gap over 5 seconds.
- Collector failures are reported separately from execution gaps; a sequence of failed API calls does not establish usable metric readings.
- Declared interruptions are evaluated separately, with a proposed recovery target of 5 seconds after iOS permits resumption. Unknown gaps cannot be excluded to improve the result.

Counts refer to attempts on the recording schedule, not bursts of catch-up samples. Repeat the chosen profile on three independent 15-minute recordings before calling it reliable. Complete at least one 60-minute recording to qualify medium sessions. The audio-only cases below remain comparison tests; DEV-08 covers the current location-only default.

| ID | Procedure | Expected result / evidence |
| --- | --- | --- |
| DEV-01 | Record two minutes in the foreground, including idle use and an identifiable workload change. Capture raw CPU/VM/interface results and API errors. | CPU and RAM have usable device sources and valid calculations. Record availability for every requested metric. Responsiveness checks supplement arithmetic checks; absolute accuracy remains unverified without an independent reference. |
| DEV-02 | Audio on, location off; use another app with no audio for 15 minutes. | Export proves continued attempts and usable core metrics under the continuity target. No location authorization request. |
| DEV-03 | Audio on, location off; run a game with sound for 15 minutes. | Sampling meets the continuity target and game audio remains audible without monitor-induced pauses, volume ducking, or route changes. |
| DEV-04 | Repeat while music is playing. Check Control Center, Lock Screen media controls, pause/resume, and track changes. | The intended media app retains its controls and metadata. The silent stream has no audible output and does not replace the media presentation. |
| DEV-05 | Audio on, location off; lock the phone for 60 minutes and unlock it. | Export establishes medium-session persistence and actual completion at the deadline. Note any OS interruption; no fabricated samples across gaps. |
| DEV-06 | During recording, independently test a phone call, Siri interaction, alarm, and microphone-using foreground app. | Foreground functions work. Every observed interruption/gap is recorded. Recovery occurs when permitted, or the run reports a distinct persistence failure and clear stale content. |
| DEV-07 | Connect/disconnect Bluetooth headphones and a wired audio accessory while another app has audio. | Foreground audio routes correctly; no audible monitor sound. Sampling persists or records interruption/recovery with a separate result for each route change. |
| DEV-08 | Audio off, location on; remain stationary using another app for 15 minutes. Repeat indoors and while walking. | Determine whether location alone qualifies as a persistence profile, including stationary use. Silent audio remains off. A failure is recorded rather than concealed by enabling audio. |
| DEV-09 | Audio and location on; repeat the game case and one audio-interruption case. | Determine whether the combination improves persistence; retain separate service events and overhead results. |
| DEV-10 | Refuse location access, then separately revoke it through Settings during an active session. | Audio preference is preserved. Permission/status messaging agrees with actual authorization and recorded service behavior. |
| DEV-11 | Repeat the 15-minute audio-only case with Low Power Mode on and, separately, Background App Refresh off. | Record support for each profile against the continuity target; app copy and final qualification match the observed result. |
| DEV-12 | Switch Wi-Fi to cellular, enable Airplane Mode, and repeat with a VPN if available. | Local recording and Live Activity use continue without a server dependency. Interface rates warm up after source changes, carry correct scope, and remain free of double-counted totals. |
| DEV-13 | Inspect compact/expanded Dynamic Island, Lock Screen, portrait/landscape, large text, and VoiceOver. | Values, units, availability, and age remain readable. Portrait and iOS 27 landscape presentations fit their available space. Accessibility labels include metric name and unit. |
| DEV-14 | Observe at least 20 Live Activity readings over a 15-minute run; then deliberately freeze collector output and separately delay ActivityKit publication in the diagnostic build. | Proposed rendered-age target: P95 at most 5 seconds while updates are delivered. Frozen content carries its old sequence/timestamp and visibly becomes stale; a moving timer is never accepted as fresh sampling. Record actual stale-transition latency. |
| DEV-15 | Stop after using another app, toggle each background setting, and let each duration preset expire. | While execution is available, the sampler and requested background services stop within 2 seconds of Stop/deadline. Terminal ActivityKit submission occurs within 2 seconds; record rendered completion/removal latency separately. Other apps' audio remains functional. |
| DEV-16 | Force-quit during recording and relaunch. | No claim of sampling after termination. Retained records are readable; the prior session is marked interrupted and a new session awaits Start. Activity presentation agrees with available final/stale state. |
| DEV-17 | Perform 20 Start/Stop cycles, including starts after interruption and permission refusal. | Each active cycle has one sampler and at most one Live Activity. Stopped cycles leave no active background service, duplicate activity, or continuing recording. |
| DEV-18 | Measure matched baseline and monitoring runs under the overhead protocol below. | Record monitor CPU, memory, battery, and thermal effects with their measurement limits. Review provisional targets against observed results. |

### Accuracy limits

A known workload and plausible values establish responsiveness, not independently calibrated whole-device accuracy. Arithmetic fixtures establish the calculations. Raw device results establish provenance and access. Record these as separate findings. If an independent reference becomes available later, add a comparison case rather than upgrading an earlier result silently.

### Overhead protocol

Use the same foreground workload, brightness, network, audio route, power mode, and approximate starting battery/thermal conditions. Compare monitor off, audio only, audio plus sampling, and the full Live Activity profile. Measure location separately before recommending both switches.

For the default profile, provisional engineering targets are average monitor CPU at most 2% of one core and at most 8 MiB footprint growth from minute 5 to minute 60, excluding any explicitly measured system/UI caches. Investigate each exceeded target; do not silently exclude retained sample history or resource leaks as cache growth.

Battery evaluation uses paired 60-minute baseline/monitoring runs, repeated three times in alternating order. Initial target: median additional discharge at most two percentage points per hour. Record the range and the coarse resolution of charge-level readings. A single pair is exploratory evidence, not a precise energy measurement. Overhead runs use compact logging and no screen recording; presentation QA may use screen recording in separate runs.

## 8. Execution order and gates

1. **Core feasibility:** CI-01, CI-03, CI-04, DEV-01, DEV-02, DEV-03, DEV-04, and DEV-15 on a minimal diagnostic build. One 15-minute run per audio profile is sufficient for this initial probe. Address inaccessible core counters, audio conflicts, persistence failure, or failed cleanup before expanding the dashboard.
2. **Automated correctness:** Implement all MET, LIF, and LA cases, then run CI-02. Complete them before the full recording/UI feature is considered correct.
3. **Session qualification:** Repeat DEV-02 through DEV-04 three times; complete DEV-05 through DEV-17 with a result for each listed variant. Qualify audio only, location only, and combined profiles separately. An optional profile that fails can remain disabled with the finding documented.
4. **Overhead review:** DEV-18 and CI-05. Decide whether to change defaults or intervals based on the measured cost.

The default location profile is qualified when its core counters, ordinary persistence, audio coexistence, stale presentation, and cleanup meet the accepted targets, the automated suites pass, and interrupted/degraded runs remain truthful. Optional-mode failures must be reflected in settings and the qualification summary. The user's successful location comparisons establish a working candidate; they do not complete the longer-session or overhead procedures.

Use [RUN_TEMPLATE.md](RUN_TEMPLATE.md) to record evidence. Leave a case Not run or Blocked until its required environment and evidence exist.

## 9. Handoff for the later development agent

- This spec and run template are local working files on `tests/test-spec`. The user requested that a later agent implement the work before creating the commit and PR. The spec-writing task does not publish these files.
- Read the user's current instructions and this spec before implementation. Preserve the repository target `IAMFreehandZ/ios-monitor` and the intended branch `tests/test-spec`.
- Start with the core-feasibility diagnostic build and a minimal GitHub build path. Simulator checks cannot settle the physical-device gate; user-provided phone results are required.
- When development is explicitly started, write meaningful failing tests for the defined contracts, implement the behavior, and verify it. Keep automated results separate from device cases awaiting the user.
- The Windows environment has no local Xcode. Use GitHub macOS runners for iOS compilation/testing and build artifacts; use Windows for signing/installing and collecting phone exports.
- A later commit/PR should describe the implementation and its actual evidence. List any pending device cases and scope changes explicitly. Do not claim that the tests in this document passed merely because the spec exists.

## 10. Source references

Sources inspected on 2026-09-29. They support platform facts and candidate mechanisms; the numeric targets in this document are proposed project requirements.

- [StikDebug background audio service](https://github.com/StikDebug/StikDebug/blob/main/StikDebug/Services/BackgroundAudioManager.swift): silent audio, mixing, interruption/recovery behavior.
- [StikDebug background location service](https://github.com/StikDebug/StikDebug/blob/main/StikDebug/Services/BackgroundLocationManager.swift): coarse location and background settings.
- [Apple audio mixing option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers): coexistence with other audio sessions.
- [Apple handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions): interruption events and recovery considerations. Check the current iOS 27 resumption APIs during implementation.
- [Apple Now Playing information](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter): media metadata presentation.
- [Apple Mach memory guidance](https://developer.apple.com/forums/thread/723334): availability of host statistics on iOS and interpretation of free memory.
- [Apple Live Activity constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities): sandbox, content-size, stale-state, and lifetime constraints.
- [Apple Live Activity stale date](https://developer.apple.com/documentation/activitykit/activitycontent/staledate): the stale content contract.
- [Apple Live Activities on iOS 27](https://developer.apple.com/videos/play/wwdc2026/223/): portrait and landscape presentations.
- [GitHub macOS runner images](https://github.com/actions/runner-images): toolchain availability and image metadata.
- [Sideloadly](https://sideloadly.io/): Windows sideloading and extension handling.
