#!/usr/bin/env python3
"""Local OTLP/JSON receiver for Codex server time-between-token histograms.

The displayed rate is 1000 / mean request TBT, not tokens / agent turn time.
Only the named histogram's sums/counts and deduplication hashes are persisted.
No prompts, tools, other metrics, or HTTP headers are stored.
"""
import argparse
import datetime as dt
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math
import re
from pathlib import Path
import sqlite3
import tempfile
import time
from zoneinfo import ZoneInfo

METRIC_NAME = "codex.responses_api_engine_service_tbt.duration_ms"
TIMEZONE = ZoneInfo("Asia/Shanghai")
CACHE_DIR = Path.home() / "Library/Application Support/VibeHUD/Monitoring"
CACHE_FILE = CACHE_DIR / "codex-speed.json"
DATABASE_FILE = CACHE_DIR / "codex-speed.sqlite"
DEFAULT_PORT = 4319
MAX_BODY = 2 * 1024 * 1024
MIN_TEXT_DURATION_MS = 250


def finite_positive(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0


def local_day(now):
    return dt.datetime.fromtimestamp(now, TIMEZONE).date().isoformat()


def empty(now=None, reason="awaiting_server_tbt"):
    now = time.time() if now is None else now
    return dict(day=local_day(now), timezone="Asia/Shanghai", updated_at=now,
                metric="output_generation", status="unavailable", reason=reason,
                tokens_per_second=None, timing_source="codex_server_tbt",
                aggregation="reciprocal_mean_request_tbt", scope="local_codex_requests",
                day_assignment="export_interval_end", sample_count=0, sum_tbt_ms=0,
                completed_turns=0, output_tokens=0, duration_ms=0)


def read_daily(path=None, now=None):
    """Read the small receiver cache; never infer speed from rollout wall time."""
    now = time.time() if now is None else now
    path = CACHE_FILE if path is None else path
    try:
        data = json.loads(Path(path).read_text())
        if not isinstance(data, dict) or data.get("day") != local_day(now):
            return empty(now)
        count, total = data.get("sample_count"), data.get("sum_tbt_ms")
        if (data.get("metric") != "output_generation" or data.get("timing_source") != "codex_server_tbt"
                or not isinstance(count, int) or isinstance(count, bool) or count <= 0
                or not finite_positive(total)):
            return empty(now)
        rate = 1000 * count / total
        if not finite_positive(rate):
            return empty(now)
        result = empty(now)
        result.update(status="ok", reason=None, tokens_per_second=rate,
                      sample_count=count, sum_tbt_ms=total,
                      updated_at=data.get("updated_at", now))
        return result
    except (OSError, ValueError, TypeError, OverflowError):
        return empty(now)


def estimate_text_daily(paths, now=None, timeout=8):
    """Estimate visible generation from timed, tool-free upstream responses.

    Codex persists ItemCompleted before TokenUsageRecord for each response.
    Only a response with one assistant message and no other non-reasoning
    generated item can assign output-minus-reasoning tokens to that message.
    Tools, reasoning, gaps between messages, and user waiting never enter time.
    """
    now = time.time() if now is None else now
    deadline = time.monotonic() + timeout
    day = local_day(now)
    result = empty(now, "no_timed_text_samples")
    result.update(timing_source="codex_message_interval", estimated=True,
                  aggregation="visible_output_tokens_over_message_intervals",
                  scope="timed_pure_text_responses", minimum_duration_ms=MIN_TEXT_DURATION_MS,
                  day_assignment="message_completion")
    seen = set()
    tokens = duration = samples = skipped_short = 0
    for path in paths:
        messages, generated = [], []
        try:
            with Path(path).open() as stream:
                for raw in stream:
                    if time.monotonic() > deadline:
                        result["reason"] = "text_scan_timeout"
                        return result
                    if not any(marker in raw for marker in ('"response_item"', '"item_completed"', '"token_usage_record"', '"task_started"', '"task_complete"', '"turn_aborted"')):
                        continue
                    try:
                        event = json.loads(raw)
                        payload = event.get("payload") or {}
                        kind = event.get("type")
                        if kind == "event_msg":
                            event_type = payload.get("type")
                            if event_type in ("task_started", "task_complete", "turn_aborted"):
                                messages, generated = [], []
                            elif event_type == "item_completed" and payload.get("item", {}).get("type") == "AgentMessage":
                                messages.append(payload)
                        elif kind == "response_item":
                            item_type = payload.get("type")
                            if item_type == "message" and payload.get("role") == "assistant":
                                metadata = event.get("metadata") or {}
                                source_id = (metadata.get("retained_source") or {}).get("id") or {}
                                generated.append(("message", payload.get("id"), source_id.get("turn_id")))
                            elif item_type not in ("message", "reasoning", "function_call_output", "custom_tool_call_output"):
                                generated.append(item_type)
                        elif kind == "token_usage_record":
                            batch, item_kinds = messages, generated
                            messages, generated = [], []
                            response = payload.get("response_id")
                            if not isinstance(response, str) or not response or response in seen:
                                continue
                            if len(batch) != 1 or len(item_kinds) != 1 or not isinstance(item_kinds[0], tuple):
                                continue
                            message = batch[0]
                            if item_kinds[0][1] != message.get("item", {}).get("id") or item_kinds[0][2] != payload.get("turn_id"):
                                continue
                            if any(message.get(key) != payload.get(key) for key in ("thread_id", "turn_id")):
                                continue
                            start, end = message.get("started_at_ms"), message.get("completed_at_ms")
                            if not all(isinstance(value, int) and not isinstance(value, bool) and value > 0 for value in (start, end)):
                                continue
                            if end > (now + 300) * 1000 or local_day(end / 1000) != day:
                                continue
                            elapsed = end - start
                            if elapsed < MIN_TEXT_DURATION_MS:
                                skipped_short += 1
                                continue
                            usage = payload.get("usage") or {}
                            output, reasoning = usage.get("output_tokens"), usage.get("reasoning_output_tokens")
                            if not all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in (output, reasoning)):
                                continue
                            visible = output - reasoning
                            if visible <= 0:
                                continue
                            seen.add(response)
                            tokens += visible
                            duration += elapsed
                            samples += 1
                    except (ValueError, TypeError, AttributeError, OverflowError):
                        continue
        except (OSError, UnicodeError):
            continue
    result.update(sample_count=samples, output_tokens=tokens, duration_ms=duration,
                  completed_turns=0, skipped_short_samples=skipped_short)
    if samples and duration:
        result.update(status="ok", reason=None, tokens_per_second=1000 * tokens / duration)
    return result


def daily_rollouts(roots, now=None):
    """Include older active sessions, without rereading inactive past days."""
    now = time.time() if now is None else now
    start = dt.datetime.combine(dt.date.fromisoformat(local_day(now)), dt.time(), TIMEZONE).timestamp()
    for root in roots:
        for path in Path(root).rglob("rollout-*.jsonl"):
            try:
                if path.stat().st_mtime >= start:
                    yield path
            except OSError:
                continue


def write_cache(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".codex-speed.", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, allow_nan=False)
            stream.flush()
            temporary.chmod(0o600)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def otlp_field(value, name, default=None):
    """Accept standard JSON names and protobuf snake_case aliases."""
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
    return value.get(name, value.get(snake, default))


def points(payload):
    """Yield validated TBT points; discard every unrelated telemetry field."""
    for resource in otlp_field(payload, "resourceMetrics", []):
        for scope in otlp_field(resource, "scopeMetrics", []):
            for metric in scope.get("metrics", []):
                if metric.get("name") != METRIC_NAME:
                    continue
                histogram = metric.get("histogram", {})
                temporality = otlp_field(histogram, "aggregationTemporality")
                if temporality not in (1, 2, "AGGREGATION_TEMPORALITY_DELTA", "AGGREGATION_TEMPORALITY_CUMULATIVE"):
                    continue
                cumulative = temporality in (2, "AGGREGATION_TEMPORALITY_CUMULATIVE")
                for point in otlp_field(histogram, "dataPoints", []):
                    try:
                        if point.get("flags", 0) & 1:
                            continue
                        raw_count = point.get("count")
                        if isinstance(raw_count, bool) or not isinstance(raw_count, (int, str)):
                            continue
                        count = int(raw_count)
                        total = point.get("sum")
                        start, end = int(otlp_field(point, "startTimeUnixNano", 0)), int(otlp_field(point, "timeUnixNano", 0))
                        if count <= 0 or count > 10**12 or not finite_positive(total) or start <= 0 or end < start:
                            continue
                        minimum = point.get("min")
                        if minimum is not None:
                            # A histogram cannot recover individual invalid samples.
                            # Refuse the point if it reports any zero/negative TBT.
                            if not finite_positive(minimum):
                                continue
                        else:
                            # Codex's explicit duration buckets start at 0 ms.
                            # Without min, accept only a complete zero-free bucket.
                            bounds, buckets = otlp_field(point, "explicitBounds", []), otlp_field(point, "bucketCounts", [])
                            if (not bounds or bounds[0] != 0 or len(buckets) != len(bounds)+1
                                    or int(buckets[0]) != 0 or sum(int(n) for n in buckets) != count):
                                continue
                        series = digest([resource.get("resource", {}), scope.get("scope", {}), point.get("attributes", [])])
                        identity = digest([series, start, end, count, total, cumulative])
                        yield identity, series, start, end, count, float(total), cumulative
                    except (ValueError, TypeError, OverflowError):
                        continue


class Store:
    def __init__(self, database=DATABASE_FILE, cache=CACHE_FILE):
        Path(database).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(database)
        Path(database).chmod(0o600)
        self.cache = Path(cache)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS seen (id TEXT PRIMARY KEY, day TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS batches (id TEXT PRIMARY KEY, day TEXT NOT NULL, count INTEGER NOT NULL, total REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS cumulative (series TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL, count INTEGER NOT NULL, total REAL NOT NULL, PRIMARY KEY(series,start));
        """)
        self.db.commit()

    def ingest(self, payload, now=None):
        now = time.time() if now is None else now
        accepted = 0
        with self.db:
            for identity, series, start, end, count, total, cumulative in points(payload):
                if end / 1e9 > now + 300:
                    continue
                day = local_day(end / 1e9)
                if self.db.execute("INSERT OR IGNORE INTO seen VALUES (?,?)", (identity, day)).rowcount == 0:
                    continue
                if cumulative:
                    previous = self.db.execute("SELECT end,count,total FROM cumulative WHERE series=? AND start=?", (series, str(start))).fetchone()
                    if previous:
                        if end <= int(previous[0]) or count < previous[1] or total < previous[2]:
                            continue
                        increment_count, increment_total = count - previous[1], total - previous[2]
                    else:
                        increment_count, increment_total = count, total
                    self.db.execute("INSERT OR REPLACE INTO cumulative VALUES (?,?,?,?,?)", (series, str(start), str(end), count, total))
                    count, total = increment_count, increment_total
                if count <= 0 or not finite_positive(total):
                    continue
                self.db.execute("INSERT INTO batches VALUES (?,?,?,?)", (identity, day, count, total))
                accepted += count
            cutoff = (dt.datetime.fromtimestamp(now, TIMEZONE).date() - dt.timedelta(days=31)).isoformat()
            self.db.execute("DELETE FROM seen WHERE day < ?", (cutoff,))
            self.db.execute("DELETE FROM batches WHERE day < ?", (cutoff,))
            cutoff_seconds = dt.datetime.combine(dt.date.fromisoformat(cutoff), dt.time(), TIMEZONE).timestamp()
            self.db.execute("DELETE FROM cumulative WHERE CAST(end AS REAL) < ?", (cutoff_seconds * 1e9,))
        self.publish(now)
        return accepted

    def publish(self, now=None):
        now = time.time() if now is None else now
        result = empty(now)
        count, total = self.db.execute("SELECT COALESCE(SUM(count),0), COALESCE(SUM(total),0) FROM batches WHERE day=?", (local_day(now),)).fetchone()
        if count > 0 and finite_positive(total):
            result.update(status="ok", reason=None, sample_count=count, sum_tbt_ms=total,
                          tokens_per_second=1000 * count / total)
        write_cache(self.cache, result)
        return result

    def close(self):
        self.db.close()


def make_server(store, port=DEFAULT_PORT):
    # Deliberately retain no bodies, attributes, arbitrary paths, or headers.
    diagnostics = dict(started_at=time.time(), post_requests=0, json_requests=0,
                       accepted_samples=0, responses={}, metric_names=[], tbt_points=[])

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            self.request.settimeout(5)
            super().setup()

        def log_message(self, *args):
            pass

        def reply(self, status, value):
            if self.command == "POST":
                key = str(status)
                diagnostics["responses"][key] = diagnostics["responses"].get(key, 0) + 1
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                self.reply(200, {"status": "ok", "metric": METRIC_NAME, "diagnostics": diagnostics})
            else:
                self.reply(404, {})

        def do_POST(self):
            diagnostics["post_requests"] += 1
            diagnostics["last_request_at"] = time.time()
            diagnostics["last_path"] = self.path if self.path in ("/v1/metrics", "/v1/metrics/v1/metrics", "/") else "other"
            diagnostics["last_content_type"] = self.headers.get("Content-Type", "").split(";")[0] if self.headers.get("Content-Type", "").split(";")[0] in ("application/json", "application/x-protobuf") else "other"
            diagnostics["last_encoding"] = self.headers.get("Content-Encoding", "identity") if self.headers.get("Content-Encoding", "identity") in ("identity", "gzip") else "other"
            if self.path != "/v1/metrics":
                self.reply(404, {})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                diagnostics["last_body_bytes"] = length
                if length <= 0 or length > MAX_BODY or self.headers.get("Transfer-Encoding"):
                    self.reply(413, {})
                    return
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError("incomplete request")
                if self.headers.get("Content-Encoding") == "gzip":
                    # Bound decompression as well as compressed request size.
                    import io
                    with gzip.GzipFile(fileobj=io.BytesIO(body)) as compressed:
                        body = compressed.read(MAX_BODY + 1)
                    if len(body) > MAX_BODY:
                        self.reply(413, {})
                        return
                elif self.headers.get("Content-Encoding", "identity") != "identity":
                    self.reply(415, {})
                    return
                payload = json.loads(body)
                if not isinstance(payload, dict):
                    raise ValueError("not an object")
                diagnostics["json_requests"] += 1
                diagnostics["schema_keys"] = [key for key in ("resourceMetrics", "resource_metrics", "metrics") if key in payload]
                names = set(diagnostics["metric_names"])
                summaries = []
                for resource in payload.get("resourceMetrics", payload.get("resource_metrics", [])):
                    diagnostics["resource_keys"] = [key for key in ("scopeMetrics", "scope_metrics", "instrumentationLibraryMetrics", "instrumentation_library_metrics") if key in resource]
                    for scope in resource.get("scopeMetrics", resource.get("scope_metrics", [])):
                        diagnostics["scope_keys"] = [key for key in ("metrics", "metric") if key in scope]
                        for metric in scope.get("metrics", []):
                            name = metric.get("name", "")
                            if isinstance(name, str) and re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_.]{1,160}", name):
                                names.add(name)
                            if name == METRIC_NAME:
                                histogram = metric.get("histogram", {})
                                diagnostics["tbt_histogram_keys"] = [key for key in ("dataPoints", "data_points", "aggregationTemporality", "aggregation_temporality") if key in histogram]
                                for point in otlp_field(histogram, "dataPoints", [])[:8]:
                                    summary = {key: otlp_field(point, key) for key in ("count", "sum", "min", "max", "flags", "startTimeUnixNano", "timeUnixNano", "explicitBounds", "bucketCounts") if otlp_field(point, key) is not None}
                                    summary["temporality"] = otlp_field(histogram, "aggregationTemporality")
                                    # Only numeric TBT fields, bounded to normal histogram sizes.
                                    summaries.append({k: v for k, v in summary.items() if isinstance(v, (int, float)) and math.isfinite(v) or isinstance(v, str) and v.isdigit() and len(v) <= 24 or isinstance(v, list) and len(v) <= 64 and all(isinstance(n, (int, float)) and math.isfinite(n) or isinstance(n, str) and n.isdigit() and len(n) <= 24 for n in v)})
                diagnostics["metric_names"] = sorted(names)[:256]
                if summaries:
                    diagnostics["tbt_points"] = summaries[:8]
                diagnostics["accepted_samples"] += store.ingest(payload)
                self.reply(200, {})
            except (ValueError, TypeError, AttributeError, OverflowError, OSError, EOFError):
                self.reply(400, {})

    return HTTPServer(("127.0.0.1", port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["serve", "status", "config"])
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--cache", type=Path, default=CACHE_FILE)
    parser.add_argument("--database", type=Path, default=DATABASE_FILE)
    args = parser.parse_args()
    if args.command == "config":
        print('[otel]\nmetrics_exporter = { otlp-http = { endpoint = "http://127.0.0.1:%d/v1/metrics", protocol = "json" } }' % args.port)
    elif args.command == "status":
        print(json.dumps(read_daily(args.cache), allow_nan=False))
    else:
        store = Store(args.database, args.cache)
        store.publish()
        server = make_server(store, args.port)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
            store.close()


if __name__ == "__main__":
    main()
