#!/usr/bin/env python3
"""Read Codex quota and text-generation measurements from local session logs.

Reads ~/.codex/sessions and ~/.codex/archived_sessions. No credentials or
network requests. --write atomically stores a quota-only JSON snapshot in
Application Support; --cache overrides that path for an existing local setup.
"""
import datetime as dt
import argparse
import importlib.util
import json
import math
import os
import sys
import tempfile
from pathlib import Path

# The app invokes Python with -I: load the bundled sibling independent of cwd.
_spec = importlib.util.spec_from_file_location("codex_speed", Path(__file__).with_name("codex_speed.py"))
_speed = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_speed)

SESSIONS_DIR = os.path.expanduser("~/.codex/sessions")
ARCHIVED_DIR = os.path.expanduser("~/.codex/archived_sessions")
DEFAULT_CACHE = Path.home() / "Library/Application Support/VibeHUD/Monitoring/codex.json"
TAIL_BYTES = 512 * 1024   # 每个文件只读末尾这么多
MAX_FILES = 10            # 按文件名、按修改时间各取最近几个作为候选
WINDOW_NAMES = {300: "five_hour", 10080: "seven_day"}


def recent_logs(roots=(SESSIONS_DIR, ARCHIVED_DIR)):
    """候选日志 = 文件名最新的 N 个 ∪ 修改时间最新的 N 个。

    只看 mtime 不可靠：Codex 会刷新旧文件的 mtime 而不写新事件；
    只看文件名也不够：早开的长会话可能还在写。最终以事件自身时间戳为准。
    """
    files = []
    for base in roots:
        for root, _, names in os.walk(base):
            for n in names:
                if n.startswith("rollout-") and n.endswith(".jsonl"):
                    p = os.path.join(root, n)
                    try:
                        files.append((n, os.path.getmtime(p), p))
                    except OSError:
                        pass
    by_name = sorted(files, reverse=True)[:MAX_FILES]
    by_mtime = sorted(files, key=lambda f: f[1], reverse=True)[:MAX_FILES]
    return list({f[2] for f in by_name + by_mtime})


def last_rate_limit_event(path):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - TAIL_BYTES))
        lines = f.read().split(b"\n")
    for raw in reversed(lines):
        if b'"rate_limits"' not in raw:
            continue
        try:
            ev = json.loads(raw)
        except ValueError:
            continue  # 可能是被截断的首行
        payload = ev.get("payload") or {}
        if payload.get("type") != "token_count" or not payload.get("rate_limits"):
            continue
        try:
            snap = to_snapshot(ev)
        except (KeyError, TypeError, ValueError, OverflowError):
            continue
        # Recent token events can carry only metadata or a different window.
        # Such an event must not replace the last real quota measurement.
        if snap["updated_at"] and any(name in WINDOW_NAMES.values() for name in snap["windows"]):
            return ev
    return None


def parse_ts(s):
    try:
        return int(dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except (AttributeError, ValueError):
        return None


def to_snapshot(ev):
    rl = ev["payload"]["rate_limits"]
    windows = {}
    for key in ("primary", "secondary"):
        w = rl.get(key)
        if not isinstance(w, dict) or w.get("used_percent") is None:
            continue
        minutes = w.get("window_minutes")
        name = WINDOW_NAMES.get(minutes, f"{minutes}m")
        try:
            used = float(w["used_percent"])
        except (TypeError, ValueError, OverflowError):
            continue
        if not math.isfinite(used):
            continue
        windows[name] = {
            "used_percentage": used,
            "resets_at": w.get("resets_at"),
        }
    return {
        "tool": "codex",
        "source": "codex-session-log",
        "updated_at": parse_ts(ev.get("timestamp")),
        "plan_type": rl.get("plan_type"),
        "windows": windows,
    }


def write_cache(snapshot, cache_file):
    cache_file = Path(cache_file)
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=cache_file.parent, prefix=".codex.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(snapshot, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, cache_file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--sessions-dir", default=SESSIONS_DIR)
    parser.add_argument("--archived-dir", default=ARCHIVED_DIR)
    args = parser.parse_args()
    try:
        with args.cache.open() as stream:
            previous = json.load(stream)
        if not isinstance(previous, dict):
            previous = {}
    except (OSError, ValueError):
        previous = {}
    snap = {"tool": "codex"}
    try:
        events = []
        for path in recent_logs((args.sessions_dir, args.archived_dir)):
            try:
                event = last_rate_limit_event(path)
                if event:
                    events.append(event)
            except (OSError, ValueError, TypeError, AttributeError):
                continue
        if events:
            snap = to_snapshot(max(events, key=lambda ev: ev.get("timestamp") or ""))
        elif previous.get("windows"):
            snap = {key: value for key, value in previous.items() if key != "daily_performance"}
        else:
            snap["error"] = "最近的会话日志里没有配额记录"
    except (OSError, ValueError, TypeError, AttributeError):
        snap = {key: value for key, value in previous.items() if key != "daily_performance"}
        snap.setdefault("tool", "codex")
        snap.setdefault("error", "配额读取失败")
    snap["daily_performance"] = _speed.estimate_text_daily(
        _speed.daily_rollouts((args.sessions_dir, args.archived_dir)))
    if args.write:
        write_cache(snap, args.cache)
    print(json.dumps(snap, ensure_ascii=False, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
