# Independent app analytics

vibe hud belongs to the **minicode** organization and sends new data exclusively to its own Mixpanel project, **vibe hud (4078940)**, in the US region. The public ingestion token and project ID are configured in Info.plist. No API secret is bundled. The previous shared project **minicode (4078569)** is retained as historical data; switching the token does not automatically move old events.

The official Mixpanel Swift SDK remains pinned to `3ad0fb82216978c124b04accac6c9f9eaf848187`. No extra client dependency is needed for regional context.

## Usage and retention

- `App Launched` records a normal launch. `Daily Active` records the first actual HUD interaction of each reporting day.
- The reporting day follows **US/Pacific** (`America/Los_Angeles`), including DST. The Mac's local timezone does not change daily deduplication.
- Each app uses its own persistent random installation identifier. Development and production have separate identifiers and SDK queues. Project migrations have separate daily bookkeeping and queues so today's use can reach the new project without resetting the installation ID.
- Counts describe installations, not people deduplicated across computers. Multiple meaningful uses and restarts on the same reporting day count once.
- Retention uses `Daily Active` as the initial and returning event. First-use cohorts measure new-installation retention; repeated-start cohorts measure activity retention. A cohort needs elapsed days and returning activity before D1/D7/D30 can have results. Missing future periods are not zero retention.
- Background work, previews and tests do not manufacture active users. Automated checks use temporary preferences and send no events.

## Regional hints

Every client event contains these coarse device-setting properties:

| Property | Meaning |
| --- | --- |
| `device_region_country` | Two-letter ISO country from the system region setting; otherwise `unknown` |
| `device_language` | Preferred language code, with the system locale language as fallback |
| `device_timezone` | Current IANA/system timezone identifier |
| `region_source` | `system_region_setting`, or `unknown` when no country setting exists |

Label the country report **Device country/region setting**. These are settings, not verified residence or current physical location. English and shared timezones cannot uniquely determine a country. The app never guesses a country from those signals, and worldwide/numeric regions remain unknown. IP-based geolocation remains disabled; no precise coordinates or location permission is used. Older events cannot acquire these fields retroactively. Regional hints are refreshed on each newly recorded active day.

The settings disclosure includes language, system region and timezone. The existing anonymous-usage switch controls all client events. Opting out prevents initialization on future launches and opts out the running SDK. No conversations, screenshots, clipboard data, files, commands, account identifiers, hardware UUIDs or session replay are sent.

## Download analysis

The central collector in [vibe-hud](https://github.com/section9-lab/vibe-hud/blob/main/scripts/sync-download-analytics.py) reads public GitHub release-asset counters for all three apps, and sends each aggregate to that app's own project. Its configuration is [analytics-projects.json](https://github.com/section9-lab/vibe-hud/blob/main/docs/analytics-projects.json).

`GitHub Download Snapshot` is an **aggregate**, with `data_kind = aggregate_downloads` and a separate aggregate identity. It never emits `Daily Active`. Only uploaded DMG assets in published stable releases count; source archives, checksums, agent-runtime archives, drafts and prereleases are excluded. Downloads include updates, repeated downloads and automated downloads, so they are not unique users or completed installations. GitHub's public counters do not provide downloader countries.

- `download_total`: total downloads of currently published matching assets at the sample time. Deleted assets are no longer in this total.
- `downloads_since_previous_snapshot`: positive per-asset increases since the previous acknowledged sample. It is **absent** on the first baseline, rather than pretending lifetime downloads happened today.
- `is_baseline`, `snapshot_date`, `previous_snapshot_time` and `counter_reset_detected` distinguish sampling gaps and counter changes.

The workflow samples daily. Increases describe the interval between samples, not exact midnight-to-midnight downloads; GitHub scheduled runs can be delayed. Cache loss or project changes establish a fresh baseline. A failed upload does not advance that app's baseline. Pending payloads and insert IDs are persisted before upload, so retries after an ambiguous acknowledgement reuse the original event instead of duplicating its delta. Aggregate events also disable IP enrichment to avoid attributing CI-server geography to users.

## Dashboard plan

Each app's project can use up to five saved report definitions on the current free plan:

1. Daily active installations: unique `Daily Active`, daily interval, last 30 days.
2. Active-installation summary: unique `Daily Active` over the selected window; switch between 7 and 30 days instead of summing daily users.
3. Retention: first `Daily Active` to returning `Daily Active`, with daily cohorts.
4. Device country/region setting: unique `Daily Active`, broken down by `device_region_country`.
5. Downloads: snapshots of `download_total` plus summed `downloads_since_previous_snapshot`, clearly labeled as asset downloads.

Usage/retention/regional reports filter `environment = production`. Each independent project accepts its own app token; project isolation separates the apps. Download reports select the aggregate event explicitly, so its collector identity cannot inflate active-user or retention counts.

## Checks

Run `xcodebuild test -project VibeHUD.xcodeproj -scheme VibeHUD -destination platform=macOS CODE_SIGNING_ALLOWED=NO`. Scenarios cover day/restart deduplication, timezone/DST, opt-out, random-ID isolation, project migration, ambiguous regions, and language/timezone disagreement. Collector checks run with `python3 -m unittest tests/test_download_analytics.py -v` in vibe-hud.
