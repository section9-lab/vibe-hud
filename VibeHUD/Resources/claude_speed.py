#!/usr/bin/env python3
"""Estimate Claude text-generation speed from local session transcripts.

Reads transcripts under ~/.claude/projects (or $CLAUDE_CONFIG_DIR/projects).
Each assistant line carries message.usage and a millisecond ISO-8601 timestamp;
api-request lines record when an API call was sent. The daily rate is visible
output tokens (output minus thinking) over request-to-last-block intervals,
deduplicated by message id, so official-subscription and gateway sessions are
counted together. No credentials are read; no network requests are made.

--write atomically merges the result into the monitoring cache under
"daily_performance", keeping quota fields owned by other writers;
--cache overrides that path for an existing local setup.
"""
import argparse
import datetime as dt
import json
import math
import os
import sys
import tempfile
import time
from pathlib import Path
from zoneinfo import ZoneInfo

TIMEZONE = ZoneInfo("Asia/Shanghai")
MIN_DURATION_MS = 250
SCAN_TIMEOUT = 8.0
SEEN_LIMIT = 100_000
MARKERS = ('"type":"assistant"', '"type":"user"', '"api-request"')


def default_root():
    config = os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude")
    return Path(config).expanduser() / "projects"


def default_cache():
    support = Path.home() / "Library/Application Support/VibeHUD/Monitoring"
    return support / "claude.json"


def local_day(now):
    return dt.datetime.fromtimestamp(now, TIMEZONE).date().isoformat()


def finite_positive(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0


def ts_ms(value):
    """Parse an ISO-8601 transcript timestamp to epoch milliseconds."""
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return int(parsed.timestamp() * 1000)


def empty(now, reason="no_samples_today"):
    return dict(day=local_day(now), timezone="Asia/Shanghai", updated_at=now,
                metric="output_generation", status="unavailable", reason=reason,
                tokens_per_second=None, timing_source="claude_transcript_request_interval",
                estimated=True,
                aggregation="visible_output_tokens_over_request_intervals",
                scope="claude_code_transcript_responses",
                day_assignment="message_completion", sample_count=0,
                output_tokens=0, duration_ms=0, minimum_duration_ms=MIN_DURATION_MS,
                skipped_short_samples=0, pairing={"api_request": 0, "prev_user_fallback": 0},
                error_rows_dropped=0, scan_truncated=False, models={})


class Aggregates:
    def __init__(self):
        self.tokens = self.ms = self.samples = self.errors = self.short = 0
        self.paired = self.fallback = 0
        self.models = {}


def discover(root, now):
    """Today's transcripts, newest first; keep older sessions still being written."""
    start = dt.datetime.combine(dt.date.fromisoformat(local_day(now)), dt.time(), TIMEZONE).timestamp()
    paths = []
    for path in Path(root).rglob("*.jsonl"):
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if mtime >= start:
            paths.append((mtime, path))
    return [path for _, path in sorted(paths, reverse=True)]


class ScanTimeout(Exception):
    """Raised past the scan deadline; TimeoutError is an OSError subclass."""


def scan_file(path, agg, seen, day, now_ms, deadline):
    """Fold one transcript into aggregates; raise ScanTimeout past the deadline."""
    active = {}
    last_request_ms = None
    last_user_ms = None

    def finalize():
        for mid, item in active.items():
            if mid in seen:
                continue
            if len(seen) >= SEEN_LIMIT:
                seen.clear()
            seen.add(mid)
            if item["err"] or item["model"] == "<synthetic>" or not item["out"]:
                agg.errors += 1
                continue
            if item["start_ms"] is None or item["last_ms"] is None:
                continue
            elapsed = item["last_ms"] - item["start_ms"]
            if elapsed < MIN_DURATION_MS:
                agg.short += 1
                continue
            if item["last_ms"] > now_ms + 300_000 or local_day(item["last_ms"] / 1000) != day:
                continue
            visible = max(0, item["out"] - (item["think"] or 0))
            if visible <= 0:
                continue
            agg.tokens += visible
            agg.ms += elapsed
            agg.samples += 1
            if item["paired"]:
                agg.paired += 1
            else:
                agg.fallback += 1
            model = item["model"] or "unknown"
            summary = agg.models.setdefault(model, {"output_tokens": 0, "duration_ms": 0})
            summary["output_tokens"] += visible
            summary["duration_ms"] += elapsed
        active.clear()

    try:
        with Path(path).open(encoding="utf-8", errors="replace") as stream:
            for raw in stream:
                if time.monotonic() > deadline:
                    raise ScanTimeout
                if not any(marker in raw for marker in MARKERS):
                    continue
                try:
                    event = json.loads(raw)
                    kind = event.get("type")
                    if kind in ("user", "api-request"):
                        stamp = ts_ms(event.get("timestamp"))
                        if stamp is None:
                            continue
                        finalize()
                        if kind == "api-request":
                            last_request_ms = stamp
                        else:
                            last_user_ms = stamp
                        continue
                    message = event.get("message") or {}
                    mid = message.get("id")
                    if kind != "assistant" or not isinstance(mid, str) or not mid:
                        continue
                    item = active.setdefault(mid, {
                        "start_ms": last_request_ms if last_request_ms is not None else last_user_ms,
                        "paired": last_request_ms is not None,
                        "last_ms": None, "out": 0, "think": 0,
                        "model": message.get("model"), "err": False})
                    last_request_ms = None  # consume: one request pairs one response
                    stamp = ts_ms(event.get("timestamp"))
                    if stamp is not None and (item["last_ms"] is None or stamp > item["last_ms"]):
                        item["last_ms"] = stamp
                    usage = message.get("usage") or {}
                    if isinstance(usage.get("output_tokens"), int) and usage["output_tokens"] > 0:
                        item["out"] = usage["output_tokens"]
                        details = usage.get("output_tokens_details") or {}
                        thinking = details.get("thinking_tokens")
                        item["think"] = thinking if isinstance(thinking, int) else 0
                    if event.get("isApiErrorMessage"):
                        item["err"] = True
                except (ValueError, TypeError, AttributeError, OverflowError):
                    continue
    except OSError:
        pass
    finalize()


def estimate_text_daily(root=None, now=None, timeout=SCAN_TIMEOUT):
    now = time.time() if now is None else now
    day = local_day(now)
    deadline = time.monotonic() + timeout
    agg = Aggregates()
    seen = set()
    paths = discover(root or default_root(), now)
    result = empty(now, "no_transcripts" if not paths else "no_samples_today")
    truncated = False
    for path in paths:
        try:
            scan_file(path, agg, seen, day, now * 1000, deadline)
        except ScanTimeout:
            truncated = True
            break
    if agg.paired and agg.fallback:
        timing_source = "claude_transcript_mixed_interval"
    elif agg.fallback:
        timing_source = "claude_transcript_prev_user_interval"
    else:
        timing_source = "claude_transcript_request_interval"
    result.update(timing_source=timing_source,
                  pairing={"api_request": agg.paired, "prev_user_fallback": agg.fallback},
                  error_rows_dropped=agg.errors, scan_truncated=truncated,
                  sample_count=agg.samples, output_tokens=agg.tokens,
                  duration_ms=agg.ms, skipped_short_samples=agg.short,
                  models=agg.models)
    if agg.samples and agg.ms:
        result.update(status="ok" if not truncated else "stale",
                      reason=None if not truncated else "scan_timeout_partial",
                      tokens_per_second=1000 * agg.tokens / agg.ms)
    elif truncated:
        result.update(reason="scan_timeout")
    return result


def merge_write(path, performance):
    """Merge daily_performance into the cache, preserving quota fields."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        loaded = json.loads(path.read_text())
    except (OSError, ValueError):
        loaded = None
    snapshot = loaded if isinstance(loaded, dict) else {}
    snapshot["daily_performance"] = performance
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent,
                                      prefix=".claude-speed.", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(snapshot, stream, allow_nan=False)
            stream.flush()
            temporary.chmod(0o600)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--cache", type=Path, default=default_cache())
    parser.add_argument("--root", type=Path, default=default_root())
    parser.add_argument("--now", type=ts_ms, default=None,
                        help="ISO-8601 timestamp, for tests")
    args = parser.parse_args()
    now = None if args.now is None else args.now / 1000
    performance = estimate_text_daily(root=args.root, now=now)
    snapshot = merge_write(args.cache, performance) if args.write else performance
    print(json.dumps(snapshot, ensure_ascii=False, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
