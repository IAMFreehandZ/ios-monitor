# iOS Monitor test run

Copy this template for each run and retain the original. Use the case IDs in [TEST_SPEC.md](TEST_SPEC.md). Every result needs evidence; document revisions and test completion are separate records.

## Run identity

| Field | Value |
| --- | --- |
| Run ID / UTC date | Unrecorded |
| Spec revision / local file hash | Unrecorded |
| App source commit / build | Unrecorded |
| GitHub Actions run / artifact | Unrecorded |
| Runner image / Xcode / SDK | Unrecorded |
| Device model / iOS version / OS build | Unrecorded |
| Signing tool / version / account type | Unrecorded |
| Installed app / extension identifiers | Unrecorded |
| Recording duration / actual elapsed time | Unrecorded |
| Sampling / Live Activity submission intervals | Unrecorded |
| Audio switch / location switch | Unrecorded |
| Location authorization / accuracy authorization | Unrecorded |
| Low Power Mode / Background App Refresh | Unrecorded |
| Audio route / foreground workload / network | Unrecorded |
| Starting battery / thermal condition | Unrecorded |

## Case results

Allowed statuses: Not run, Blocked, Pass, Fail. Give each procedure variant its own row. Use a result ID such as `DEV-06 / phone-call`; it inherits the case's acceptance criteria.

| Case / variant | Status | Expected result | Observed result | Evidence path or link | Issue / follow-up |
| --- | --- | --- | --- | --- | --- |
| Unselected | Not run | Copy the acceptance criterion | Unrecorded | Unrecorded | Unrecorded |

## Capability findings

| Metric | Availability / source / scope | Arithmetic verified | Device access verified | Responsiveness verified | Independent accuracy reference |
| --- | --- | --- | --- | --- | --- |
| Device CPU | Unrecorded | Not run | Not run | Not run | Unavailable unless supplied |
| Device RAM | Unrecorded | Not run | Not run | Not run | Unavailable unless supplied |
| Interface rates | Unrecorded | Not run | Not run | Not run | Unavailable unless supplied |
| GPU / Neural Engine / disk throughput | Unrecorded | Not run | Not run | Not run | Unavailable unless supplied |

## Continuity and presentation

| Measurement | Observed value |
| --- | --- |
| Scheduled eligible slots / distinct attempts / coverage | Unrecorded |
| Valid CPU samples / valid RAM samples | Unrecorded |
| P50 / P95 / maximum attempt interval | Unrecorded |
| Unexplained gaps and duration | Unrecorded |
| Recorded interruptions / permitted-resumption-to-recovery delay | Unrecorded |
| Visible sample-age checks / P95 age | Unrecorded |
| Stale-transition latency | Unrecorded |
| Stop-to-service-release / terminal-submission / rendered-end latency | Unrecorded |

## Overhead, when measured

Record the matched baseline/monitoring pairs, ordering, duration, conditions, and mode. Include monitor CPU units, initial/final footprint, battery endpoints, thermal changes, and the resolution or limitations of each measurement. Presentation recordings and overhead runs need separate evidence.

## Evidence inventory

- Session summary JSON: Unrecorded.
- Sample/event JSON Lines: Unrecorded.
- Automated result bundle and build logs: Unrecorded.
- Presentation captures, if used: Unrecorded.
- API errors and interruption chronology: Unrecorded.

## Qualification decision

State which gate and background profile this run establishes, any unmet targets, and remaining Not run or Blocked cases. Record a proposed change to an acceptance target as a spec revision, not as a passing result under the old target.
