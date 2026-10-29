"""Offline smoke checks for bundled worker output and cache isolation."""

import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


WORKERS = Path(__file__).resolve().parents[1] / "VibeHUD/Resources"


class MonitoringWorkerTests(unittest.TestCase):
    def test_codex_quota_from_synthetic_rollout(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            sessions = home / ".codex/sessions"
            sessions.mkdir(parents=True)
            timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
            event = {
                "timestamp": timestamp,
                "payload": {
                    "type": "token_count",
                    "rate_limits": {
                        "plan_type": "plus",
                        "primary": {"window_minutes": 300, "used_percent": 85, "resets_at": 4102444800},
                        "secondary": {"window_minutes": 10080, "used_percent": 30, "resets_at": 4102444800},
                    },
                },
            }
            (sessions / "rollout-sample.jsonl").write_text(json.dumps(event) + "\n")
            cache = home / "private/codex.json"
            result = subprocess.run(
                [sys.executable, "-I", str(WORKERS / "codex_usage.py"), "--write", "--cache", str(cache),
                 "--sessions-dir", str(sessions), "--archived-dir", str(home / "archived")],
                capture_output=True, text=True, check=True,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["windows"]["five_hour"]["used_percentage"], 85)
            self.assertEqual(payload["windows"]["seven_day"]["used_percentage"], 30)
            self.assertEqual(json.loads(cache.read_text()), payload)
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)

    def test_claude_statusline_from_synthetic_input(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "claude.json"
            cache.write_text(json.dumps({"daily_performance": {"tokens_per_second": 42}}))
            result = subprocess.run(
                [sys.executable, "-I", str(WORKERS / "claude_statusline.py"), "--cache", str(cache)],
                input=json.dumps({"model": {"display_name": "Sample"}, "rate_limits": {
                    "five_hour": {"used_percentage": 22, "resets_at": None},
                    "seven_day": {"used_percentage": 61, "resets_at": None},
                }}), capture_output=True, text=True, check=True,
            )
            self.assertIn("5h 22%", result.stdout)
            self.assertIn("7d 61%", result.stdout)
            self.assertEqual(json.loads(cache.read_text())["windows"]["seven_day"]["used_percentage"], 61)
            self.assertEqual(json.loads(cache.read_text())["daily_performance"]["tokens_per_second"], 42)
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)

    def test_claude_speed_from_empty_synthetic_root_preserves_quota(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            projects = home / "projects"
            projects.mkdir()
            cache = home / "private/claude.json"
            cache.parent.mkdir()
            cache.write_text(json.dumps({"windows": {"five_hour": {"used_percentage": 22}}}))
            result = subprocess.run(
                [sys.executable, "-I", str(WORKERS / "claude_speed.py"), "--write",
                 "--root", str(projects), "--cache", str(cache)],
                capture_output=True, text=True, check=True,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["windows"]["five_hour"]["used_percentage"], 22)
            self.assertEqual(payload["daily_performance"]["status"], "unavailable")
            self.assertEqual(payload["daily_performance"]["reason"], "no_transcripts")
            self.assertEqual(json.loads(cache.read_text()), payload)
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)

    def test_claude_speed_from_synthetic_response(self):
        with tempfile.TemporaryDirectory() as directory:
            projects = Path(directory) / "projects"
            projects.mkdir()
            transcript = projects / "sample.jsonl"
            events = [
                {"type": "api-request", "timestamp": "2000-01-01T11:59:55+08:00"},
                {"type": "assistant", "timestamp": "2000-01-01T11:59:57+08:00",
                 "message": {"id": "sample-response", "model": "sample-model", "usage": {
                     "output_tokens": 80, "output_tokens_details": {"thinking_tokens": 20}}}},
            ]
            transcript.write_text("".join(json.dumps(event, separators=(",", ":")) + "\n"
                                          for event in events))
            result = subprocess.run(
                [sys.executable, "-I", str(WORKERS / "claude_speed.py"),
                 "--root", str(projects), "--now", "2000-01-01T12:00:00+08:00"],
                capture_output=True, text=True, check=True,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["status"], "ok")
            self.assertEqual(payload["sample_count"], 1)
            self.assertEqual(payload["tokens_per_second"], 30)


if __name__ == "__main__":
    unittest.main()
