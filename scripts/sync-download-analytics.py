#!/usr/bin/env python3
"""Send public GitHub DMG download snapshots to each app's own Mixpanel project.

These are aggregate asset downloads (including updates/repeated downloads), not
people, installs, or activity. The first sample establishes a baseline; it never
pretends that lifetime downloads happened today. Uses only the Python stdlib.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import NAMESPACE_URL, uuid5
from datetime import datetime, timezone
from zoneinfo import ZoneInfo


def request_json(url: str, payload: object | None = None) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "Accept": "application/json",
        "User-Agent": "minicode-download-analytics/1",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    for attempt in range(3):
        try:
            with urlopen(Request(url, data=data, headers=headers), timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            if attempt == 2 or (error.code < 500 and error.code != 429):
                raise
        except (URLError, TimeoutError):
            if attempt == 2:
                raise
        time.sleep(2 ** attempt)
    raise RuntimeError("Request did not complete")


def release_assets(releases: list[dict], suffixes: list[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        for asset in release.get("assets", []):
            if asset.get("state") != "uploaded":
                continue
            if not asset.get("name", "").lower().endswith(tuple(suffixes)):
                continue
            count = asset["download_count"]
            if not isinstance(count, int) or isinstance(count, bool) or count < 0:
                raise ValueError("GitHub returned an invalid download count")
            counts[str(asset["id"])] = count
    return counts


def fetch_assets(repository: str, suffixes: list[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for page in range(1, 101):
        releases = request_json(
            f"https://api.github.com/repos/{repository}/releases?per_page=100&page={page}"
        )
        if not isinstance(releases, list):
            raise ValueError("GitHub did not return a release list")
        counts.update(release_assets(releases, suffixes))
        if len(releases) < 100:
            return counts
    raise RuntimeError("Release pagination exceeded the supported limit; no partial sample sent")


def snapshot_event(app: dict, assets: dict[str, int], previous: dict | None,
                   timestamp: int, reporting_timezone: str) -> dict:
    same_destination = previous and previous.get("project_id") == app["project_id"]
    prior_assets = previous.get("assets", {}) if same_destination else None
    properties = {
        "token": app["token"],
        "distinct_id": f"aggregate-downloads:{app['app_id']}",
        "$insert_id": str(uuid5(NAMESPACE_URL,
                                f"github-downloads:{app['project_id']}:{app['app_id']}:{timestamp}")),
        "time": timestamp,
        "ip": "0",
        "app_id": app["app_id"],
        "app_name": app["app_name"],
        "environment": "production",
        "data_kind": "aggregate_downloads",
        "download_source": "github_releases",
        "download_scope": "published_stable_dmg_assets",
        "download_total": sum(assets.values()),
        "download_asset_count": len(assets),
        "snapshot_date": datetime.fromtimestamp(timestamp, ZoneInfo(reporting_timezone)).date().isoformat(),
        "is_baseline": prior_assets is None,
    }
    if prior_assets is not None:
        # Asset-wise deltas survive removed/replaced assets without hiding new downloads.
        properties["downloads_since_previous_snapshot"] = sum(
            max(0, count - prior_assets.get(asset_id, 0)) for asset_id, count in assets.items()
        )
        properties["counter_reset_detected"] = any(
            count < prior_assets.get(asset_id, 0) for asset_id, count in assets.items()
        )
        properties["previous_snapshot_time"] = previous["time"]
    return {"event": "GitHub Download Snapshot", "properties": properties}


def track(event: dict) -> None:
    result = request_json("https://api.mixpanel.com/track?verbose=1&ip=0", [event])
    if not isinstance(result, dict) or result.get("status") != 1:
        raise RuntimeError("Mixpanel rejected the download snapshot; baseline was not advanced")


def write_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(path)


def sync_app(app: dict, state: dict, state_path: Path, timestamp: int,
             reporting_timezone: str, dry_run: bool = False) -> dict:
    pending = state.get("pending", {}).get(app["app_id"])
    if pending and pending["destination"]["project_id"] == app["project_id"]:
        # Reuse the exact payload and insert ID after an ambiguous network outcome.
        # Never recount its delta using a new timestamp on the next workflow run.
        event = pending["event"]
        destination = pending["destination"]
    else:
        assets = fetch_assets(app["repository"], app["artifact_suffixes"])
        previous = state["apps"].get(app["app_id"])
        event = snapshot_event(app, assets, previous, timestamp, reporting_timezone)
        destination = {"project_id": app["project_id"], "time": timestamp, "assets": assets}
    if not dry_run:
        state.setdefault("pending", {})[app["app_id"]] = {
            "event": event, "destination": destination,
        }
        write_state(state_path, state)
        track(event)
        # Persist each acknowledged app so a later app's failure cannot replay its delta.
        state["apps"][app["app_id"]] = destination
        del state["pending"][app["app_id"]]
        write_state(state_path, state)
    properties = event["properties"]
    return {
        "app_id": app["app_id"], "project_id": app["project_id"],
        "download_total": properties["download_total"],
        "downloads_since_previous_snapshot": properties.get("downloads_since_previous_snapshot"),
        "is_baseline": properties["is_baseline"], "dry_run": dry_run,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1] / "docs/analytics-projects.json")
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--app", help="Only sync this app_id")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    state = json.loads(args.state.read_text()) if args.state.exists() else {"version": 1, "apps": {}}
    if state.get("version") != 1 or not isinstance(state.get("apps"), dict):
        raise ValueError("Unknown download state format; refusing to overwrite it")
    apps = [app for app in config["apps"] if not args.app or app["app_id"] == args.app]
    if not apps:
        raise ValueError("No matching app in the analytics manifest")
    timestamp = int(datetime.now(timezone.utc).timestamp())
    failed = False
    for app in apps:
        try:
            print(json.dumps(sync_app(app, state, args.state, timestamp,
                                      config["reporting_timezone"], args.dry_run)))
        except Exception as error:
            failed = True
            print(f"{app['app_id']}: {type(error).__name__}: {error}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
