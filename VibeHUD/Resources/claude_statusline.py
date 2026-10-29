#!/usr/bin/env python3
"""Claude Code status line adapter for quota fields supplied on stdin.

The command writes only five-hour and seven-day percentages to Application
Support and prints a compact status line. It does not read credentials or use
the network. Use --cache to match a custom VibeHUD monitoring cache directory.
"""
import json
import argparse
import os
import sys
import tempfile
import time

DEFAULT_CACHE = os.path.expanduser("~/Library/Application Support/VibeHUD/Monitoring/claude.json")
WINDOWS = ("five_hour", "seven_day")


def extract_windows(rate_limits):
    out = {}
    for name in WINDOWS:
        w = rate_limits.get(name)
        if isinstance(w, dict) and w.get("used_percentage") is not None:
            out[name] = {
                "used_percentage": float(w["used_percentage"]),
                "resets_at": w.get("resets_at"),
            }
    return out


def write_cache(windows, cache_file=DEFAULT_CACHE):
    cache_dir = os.path.dirname(cache_file)
    os.makedirs(cache_dir, exist_ok=True)
    # Merge, not overwrite: keep fields owned by other writers (daily_performance).
    try:
        with open(cache_file) as stream:
            previous = json.load(stream)
    except (OSError, ValueError):
        previous = {}
    if not isinstance(previous, dict):
        previous = {}
    payload = {
        "tool": "claude",
        "source": "claude-code-statusline",
        "updated_at": int(time.time()),
        "windows": windows,
    }
    merged = {**previous, **payload}
    fd, tmp = tempfile.mkstemp(dir=cache_dir, prefix=".claude.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(merged, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, cache_file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", default=DEFAULT_CACHE)
    args = parser.parse_args()
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("")
        return
    model = (data.get("model") or {}).get("display_name") or ""
    windows = extract_windows(data.get("rate_limits") or {})
    # 本次没有配额字段（如会话刚开始）时不覆盖旧缓存
    if windows:
        try:
            write_cache(windows, args.cache)
        except OSError:
            pass  # 写缓存失败不能影响状态栏显示
    parts = [f"[{model}]"] if model else []
    labels = {"five_hour": "5h", "seven_day": "7d"}
    for name in WINDOWS:
        if name in windows:
            parts.append(f"{labels[name]} {windows[name]['used_percentage']:.0f}%")
    print(" · ".join(parts))


if __name__ == "__main__":
    main()
