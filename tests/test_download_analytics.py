import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-download-analytics.py"
SPEC = importlib.util.spec_from_file_location("download_analytics", SCRIPT)
analytics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analytics)

APP = {"app_id": "pi-work", "app_name": "pi-work", "repository": "section9-lab/pi-work",
       "project_id": 4078925, "token": "test-only", "artifact_suffixes": [".dmg"]}


class DownloadAnalyticsTests(unittest.TestCase):
    def test_only_published_stable_installers_count(self):
        def release(name, count, **flags):
            return {"assets": [{"id": name, "name": name, "state": "uploaded",
                                 "download_count": count}], **flags}
        self.assertEqual(analytics.release_assets([
            release("a.dmg", 10), release("b.DMG", 4), release("SHA256SUMS.txt", 50),
            release("runtime.zip", 20), release("draft.dmg", 100, draft=True),
            release("preview.dmg", 100, prerelease=True),
        ], [".dmg"]), {"a.dmg": 10, "b.DMG": 4})

    def test_first_snapshot_does_not_invent_daily_downloads(self):
        props = analytics.snapshot_event(APP, {"1": 200}, None, 1793332800,
                                         "America/Los_Angeles")["properties"]
        self.assertEqual(props["download_total"], 200)
        self.assertTrue(props["is_baseline"])
        self.assertNotIn("downloads_since_previous_snapshot", props)

    def test_removed_assets_do_not_erase_new_downloads(self):
        previous = {"project_id": APP["project_id"], "time": 1,
                    "assets": {"removed": 1000, "existing": 10}}
        props = analytics.snapshot_event(APP, {"existing": 12, "new": 8}, previous,
                                         1793332800, "America/Los_Angeles")["properties"]
        self.assertEqual(props["downloads_since_previous_snapshot"], 10)
        self.assertEqual(props["download_total"], 20)

    def test_project_migration_establishes_a_new_baseline(self):
        previous = {"project_id": 1, "time": 1, "assets": {"1": 100}}
        props = analytics.snapshot_event(APP, {"1": 110}, previous, 1793332800,
                                         "America/Los_Angeles")["properties"]
        self.assertTrue(props["is_baseline"])
        self.assertNotIn("downloads_since_previous_snapshot", props)

    def test_aggregate_identity_cannot_be_mistaken_for_daily_activity(self):
        event = analytics.snapshot_event(APP, {}, None, 1793332800, "America/Los_Angeles")
        self.assertEqual(event["event"], "GitHub Download Snapshot")
        self.assertEqual(event["properties"]["distinct_id"], "aggregate-downloads:pi-work")
        self.assertEqual(event["properties"]["data_kind"], "aggregate_downloads")
        self.assertEqual(event["properties"]["ip"], "0")
        self.assertEqual(event, analytics.snapshot_event(APP, {}, None, 1793332800,
                                                       "America/Los_Angeles"))

    def test_baseline_is_not_advanced_after_a_rejected_sample(self):
        state = {"version": 1, "apps": {}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            with patch.object(analytics, "fetch_assets", return_value={"1": 5}), \
                 patch.object(analytics, "track", side_effect=RuntimeError("rejected")):
                with self.assertRaises(RuntimeError):
                    analytics.sync_app(APP, state, path, 1793332800, "America/Los_Angeles")
            self.assertEqual(state["apps"], {})
            self.assertTrue(path.exists())
            self.assertIn("pi-work", json.loads(path.read_text())["pending"])

    def test_ambiguous_acknowledgement_reuses_payload_after_restart(self):
        state = {"version": 1, "apps": {
            "pi-work": {"project_id": APP["project_id"], "time": 1, "assets": {"1": 2}}
        }}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            with patch.object(analytics, "fetch_assets", return_value={"1": 5}), \
                 patch.object(analytics, "track", side_effect=TimeoutError("ack lost")) as first:
                with self.assertRaises(TimeoutError):
                    analytics.sync_app(APP, state, path, 1793332800, "America/Los_Angeles")
            restarted = json.loads(path.read_text())
            with patch.object(analytics, "fetch_assets") as fetch, \
                 patch.object(analytics, "track") as retry:
                analytics.sync_app(APP, restarted, path, 1793336400, "America/Los_Angeles")
            fetch.assert_not_called()
            self.assertEqual(first.call_args, retry.call_args)
            self.assertEqual(restarted["apps"]["pi-work"]["assets"], {"1": 5})
            self.assertEqual(restarted["pending"], {})

    def test_a_successful_app_is_persisted_independently(self):
        state = {"version": 1, "apps": {}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            with patch.object(analytics, "fetch_assets", return_value={"1": 5}), \
                 patch.object(analytics, "track"):
                analytics.sync_app(APP, state, path, 1793332800, "America/Los_Angeles")
            self.assertTrue(path.exists())
            self.assertEqual(state["apps"]["pi-work"]["assets"], {"1": 5})

    def test_pagination_counts_more_than_the_first_hundred_releases(self):
        def release(asset_id):
            return {"assets": [{"id": asset_id, "name": "app.dmg", "state": "uploaded",
                                 "download_count": 1}]}
        with patch.object(analytics, "request_json", side_effect=[
            [release(index) for index in range(100)], [release(100)]
        ]) as fetch:
            self.assertEqual(sum(analytics.fetch_assets("section9-lab/pi-work", [".dmg"]).values()), 101)
            self.assertEqual(fetch.call_count, 2)


if __name__ == "__main__":
    unittest.main()
