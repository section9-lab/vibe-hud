#!/usr/bin/env python3
"""Public Tibo announcement monitor. No credentials or third-party packages."""
import argparse
import datetime as dt
import email.utils
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.request

SOURCE = "https://codex-reset.com/"
FEED = SOURCE + "api/feed"
INTERVAL = 120
MAX_BYTES = 512 * 1024
USER_AGENT = "VibeHUD/1.0 (desktop monitor)"
CACHE = Path.home() / "Library/Application Support/VibeHUD/Monitoring/tibo-reset.json"
POST_URL = re.compile(r"https://x\.com/thsottiaux/status/([0-9]{10,25})\Z")


def timestamp(value):
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError, AttributeError):
        return 0


def classify(text, context=False):
    """Conservative wording classification; never verifies an account reset."""
    text = text.lower().replace("’", "'")
    if re.search(r"\b(password|factory|git|device|router|conversation|context window)\b.{0,30}\breset|\breset\b.{0,30}\b(password|factory|device|router|conversation|context window)\b", text):
        return None
    if re.search(r"^\s*(how|when|why|can|could|would|should)\b.*\?", text):
        return None
    if re.search(r"\b(no|not|never|won't|cannot|can't|isn't|aren't|don't|didn't|haven't|hasn't)\b.{0,45}\breset|\breset\b.{0,15}\b(not happening|cancelled|canceled)\b", text):
        return None
    reset = re.search(r"\breset(?:s|ting|ted)?\b|\breseting\b", text)
    quota = re.search(r"\b(codex|usage|quota|rate limits?|limits?|banked)\b", text)
    if not reset:
        if context and re.fullmatch(r"\s*(?:done(?: and dusted)?|it's done|all propagated)[.!\s]*", text):
            return "banked" if context == "banked" else "reported"
        if context and re.search(r"\blanding\b|\blands\b", text):
            return "banked" if context == "banked" else "planned"
        return None
    if re.search(r"\b(how|when|why)\b.{0,35}\breset|\basking\b.{0,40}\bresets?\b|\breset\b.{0,25}\b(button|poster)\b", text) and not quota:
        return None
    if not quota and not context:
        # The ship-or-reset series is a signal, without enough evidence of completion.
        return "mentioned" if re.search(r"\bday\s*\d+\s*/", text) else None
    if re.search(r"\bbanked\s+resets?\b", text):
        return "banked"
    if re.search(r"\b(will|we'll|going to|soon|tomorrow|landing|lands|within|next|by eod)\b", text):
        return "planned"
    if re.search(r"\b(have|has|just|now|already)\b.{0,35}\breset|\breset\b.{0,50}\b(done|applied|propagated)|\breset (?:the )?(?:usage|rate|codex) limits?\b", text):
        return "reported"
    return "mentioned"


def normalize(feed, now):
    if not isinstance(feed, dict) or feed.get("stale") is not False:
        raise ValueError("source_stale")
    fetched = timestamp(feed.get("fetched_at"))
    if not fetched or now - fetched > 1800 or fetched > now + 300:
        raise ValueError("source_stale")
    if feed.get("profile", {}).get("handle", "").lower() != "thsottiaux":
        raise ValueError("wrong_account")
    if not isinstance(feed.get("tweets"), list) or not feed["tweets"]:
        raise ValueError("invalid_feed")
    posts = []
    for item in feed["tweets"][:300]:
        if not isinstance(item, dict):
            continue
        url = item.get("url", "")
        match = POST_URL.fullmatch(url) if isinstance(url, str) else None
        at = timestamp(item.get("at"))
        text = item.get("text")
        if not match or match[1] != str(item.get("id")) or not at or at > now + 300 or not isinstance(text, str):
            continue
        posts.append({"id": match[1], "url": url, "text": text[:5000], "at": at,
                      "parent": str(item.get("in_reply_to_tweet_id") or "")})
    if not posts:
        raise ValueError("invalid_feed")
    return sorted(posts, key=lambda p: (p["at"], p["id"])), fetched


def apply_feed(state, feed, now):
    posts, fetched = normalize(feed, now)
    result = dict(state)
    seen = set(state.get("seen", []))
    baseline = state.get("baseline_at")
    kinds = dict(state.get("contexts", {}))
    alert = state.get("alert")
    for post in posts:
        kind = classify(post["text"], kinds.get(post["parent"], False))
        if kind:
            kinds[post["id"]] = kind
        if baseline is not None and post["id"] not in seen and post["at"] > baseline and kind:
            alert = {k: post[k] for k in ("id", "url", "text", "at")}
            alert["kind"] = kind
        seen.add(post["id"])
    if baseline is None:
        result["baseline_at"] = now  # First successful read silently establishes history.
    result.update(status="ok", checked_at=now, last_success=now, source_at=fetched,
                  next_check=now + INTERVAL, failures=0, error=None,
                  seen=sorted(seen, key=int)[-500:],
                  contexts=dict(sorted(kinds.items(), key=lambda row: int(row[0]))[-300:]), alert=alert)
    return result


def failed(state, now, error, retry_after=0):
    result = dict(state)
    failures = min(int(state.get("failures", 0)) + 1, 10)
    delay = max(min(INTERVAL * (2 ** (failures - 1)), 3600), retry_after)
    result.update(status="error", checked_at=now, error=error,
                  failures=failures, next_check=now + delay)
    return result


def fetch_feed():
    request = urllib.request.Request(FEED, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.geturl() != FEED:
            raise ValueError("unexpected_redirect")
        if "application/json" not in response.headers.get("Content-Type", ""):
            raise ValueError("invalid_content_type")
        body = response.read(MAX_BYTES + 1)
        if len(body) > MAX_BYTES:
            raise ValueError("feed_too_large")
        return json.loads(body)


def read_state(path):
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) and data.get("version") == 1 else {}
    except (OSError, ValueError):
        return {}


def write_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(dict(state, version=1, source=SOURCE), ensure_ascii=False))
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def run(path, now=None):
    now = time.time() if now is None else now
    state = read_state(path)
    if now < state.get("next_check", 0):
        return state
    try:
        state = apply_feed(state, fetch_feed(), now)
    except urllib.error.HTTPError as exc:
        retry = exc.headers.get("Retry-After", "0")
        try:
            delay = max(0, int(retry))
        except ValueError:
            try:
                delay = max(0, email.utils.parsedate_to_datetime(retry).timestamp() - now)
            except (TypeError, ValueError):
                delay = 0
        state = failed(state, now, "http_" + str(exc.code), delay)
    except Exception as exc:
        code = str(exc) if isinstance(exc, ValueError) and str(exc) in {
            "source_stale", "wrong_account", "invalid_feed", "unexpected_redirect", "invalid_content_type", "feed_too_large"
        } else "network_or_invalid_data"
        state = failed(state, now, code)
    write_state(path, state)
    return state


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()
    output = run(args.cache)
    print(json.dumps({k: output.get(k) for k in ("status", "checked_at", "next_check", "error")}, ensure_ascii=False))
