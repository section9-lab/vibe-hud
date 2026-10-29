# Shared Mixpanel analytics

The owner's project is **minicode**, project ID **4078569**, using US data residency and the **US/Pacific** reporting timezone. Its public ingestion token is configured as `MixpanelProjectToken` in `VibeHUD/Info.plist`. The app uses the existing pinned Mixpanel Swift dependency.

## Event contract for all six apps

| Field | Meaning | vibe hud value |
| --- | --- | --- |
| `app_id` | Stable application identifier; filter or break down by this | `vibe-hud` |
| `app_name` | Display name | `vibe hud` |
| `app_version` | Marketing version | Bundle version |
| `build_number` | Build number | Bundle build |
| `platform` | Operating platform | `macOS` |
| `environment` | Build type; exclude development events from product metrics | `production` / `development` |
| `macos_version` | OS version | Current OS version |
| `distinct_id` | App ID plus a random, persisted installation UUID | `vibe-hud:<random UUID>` |

| Event | Trigger |
| --- | --- |
| `App Launched` | Normal application launch; excluded from tests |
| `Daily Active` | First real HUD interaction of the reporting day |

`Daily Active` includes `activity_date` as `YYYY-MM-DD`. Opening the HUD by click/hover, clicking inside an open panel, viewing a conversation, or using an approval button counts as interaction. Boot animations, automatic notification expansion, file watching, session creation and background processing do not.

Use `America/Los_Angeles` for daily deduplication in every app, matching this project's US/Pacific timezone. Calendar arithmetic handles daylight saving changes. The last reported day is persisted across app restarts; the app checks again on the next interaction, so remaining open overnight does not prevent future daily events. If the project timezone changes, update the applications' reporting timezone as well.

Anonymous identifiers are scoped to each app. They measure active installations, not people deduplicated across devices or apps. Never reuse a hardware identifier or a shared machine identifier to join these records.

## Dashboard

In Mixpanel Insights, select **Daily Active**, measure **Unique Users**, use a daily interval, filter **environment = production**, and break down by **app_id**. This gives each app's daily active installations in one report. Filter `app_id = vibe-hud` to inspect this app alone. For weekly/monthly active installations, count unique users over the relevant week/month rather than summing daily counts. Retention can use **Daily Active** as both the initial and returning event.

All six apps share the free monthly event allowance. This implementation sends at most one `Daily Active` event per active installation per reporting day, plus app launches and occasional SDK identity/opt-in events. Automatic lifecycle events, session replays, People profiles and feature-flag requests are not enabled.

## Privacy and verification

The settings menu has a **Share Anonymous Usage** switch. Disabled installations do not initialize analytics on launch, and disabling an already running client opts it out. No conversation text, prompt, command, tool result, project path, session ID, hardware UUID or agent version is included. IP-based geolocation is disabled.

Verify from a normal app build by opening the HUD, then inspect Mixpanel's Events view for `App Launched` and `Daily Active` with `app_id = vibe-hud`. Repeated interactions and a restart on the same reporting day must not produce a second `Daily Active`. Development/test validation events should be filtered from product metrics; automated tests use isolated local preferences and send no network events.
