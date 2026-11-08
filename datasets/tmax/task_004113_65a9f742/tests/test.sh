#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

UPSTREAM_PID=""
MONITOR_PID=""

cleanup() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi
    if [ -n "$UPSTREAM_PID" ]; then
        kill "$UPSTREAM_PID" 2>/dev/null || true
        wait "$UPSTREAM_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Remove stale listeners so the submitted worker is tested against fresh,
# verifier-generated upstream data rather than its own pre-existing state.
python3 - <<'PY'
import os, signal
ports = {8081, 9090}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        try:
            port = int(fields[1].rsplit(':', 1)[1], 16)
        except Exception:
            continue
        if port in ports and fields[3] == '0A':
            inodes.add(fields[9])
for pid in os.listdir('/proc'):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        for fd in os.listdir('/proc/%s/fd' % pid):
            try:
                target = os.readlink('/proc/%s/fd/%s' % (pid, fd))
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except (OSError, ProcessLookupError):
        pass
PY
sleep 1

if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
    redis-server --daemonize yes >/tmp/verifier_redis_start.log 2>&1
    sleep 1
fi
if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "Redis could not be started" >&2
    exit 0
fi
redis-cli -p 6379 FLUSHALL >/dev/null 2>&1 || exit 0

# Build a runtime-randomized source containing 1000 unique multilingual records
# and interspersed duplicates. The answers therefore cannot be hard-coded.
cat > /tmp/verifier_upstream.py <<'PY'
import hashlib
import http.server
import json
import os
import secrets
import threading

manifest_path = '/tmp/verifier_manifest.json'
served_path = '/tmp/verifier_served.jsonl'
texts = [
    'Hello, 世界 🌍',
    'Привет мир',
    'مرحبا بالعالم',
    'नमस्ते दुनिया',
    'Café déjà vu',
]
categories = ['A', 'B', 'C', 'D']
records = []
for ci, category in enumerate(categories):
    for j in range(250):
        rid = '%s-%s' % (secrets.token_hex(12), secrets.token_hex(4))
        value = ((ci + 1) * 1000 + j * 7 + secrets.randbelow(7)) / 10000.0
        records.append({
            'id': rid,
            'text': texts[(j + ci) % len(texts)],
            'category': category,
            'value': value,
        })
sequence = []
for i, record in enumerate(records):
    sequence.append(record)
    if i % 4 == 0:
        sequence.append(record)
with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(records, f, ensure_ascii=False)
open(served_path, 'w').close()

class State:
    successful = 0
    requests = 0
    lock = threading.Lock()

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path != '/stream':
            self.send_error(404)
            return
        with State.lock:
            State.requests += 1
            request_no = State.requests
            # Exercise retry behavior without consuming a source record.
            if request_no % 19 == 0:
                self.close_connection = True
                return
            record = sequence[State.successful % len(sequence)]
            State.successful += 1
            with open(served_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
        body = (json.dumps(record, ensure_ascii=False) + '\n').encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

Server(('127.0.0.1', 8081), Handler).serve_forever()
PY

python3 /tmp/verifier_upstream.py >/tmp/verifier_upstream.log 2>&1 &
UPSTREAM_PID=$!
for _ in $(seq 1 50); do
    [ -s /tmp/verifier_manifest.json ] && break
    sleep 0.1
done
if [ ! -s /tmp/verifier_manifest.json ]; then
    echo "Controlled upstream failed to start" >&2
    exit 0
fi

: > /tmp/redis_monitor.log
stdbuf -oL redis-cli -p 6379 MONITOR > /tmp/redis_monitor.log 2>&1 &
MONITOR_PID=$!
sleep 1

cd /home/user/etl_worker || exit 0
if [ ! -f worker.c ] || [ ! -f Makefile ]; then
    echo "Worker source or Makefile is missing" >&2
    exit 0
fi
rm -f worker output_clean.jsonl output.jsonl
if ! make >/tmp/verifier_make.log 2>&1; then
    cat /tmp/verifier_make.log >&2
    exit 0
fi
if [ ! -x ./worker ]; then
    echo "Makefile did not produce an executable worker" >&2
    exit 0
fi

nohup ./worker >/tmp/verifier_worker.log 2>&1 &
WORKER_PID=$!

READY=0
for _ in $(seq 1 120); do
    if curl -sf --max-time 1 http://127.0.0.1:9090/stats 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if isinstance(d.get("total_unique"),int) and d["total_unique"]>=1000 else 1)' >/dev/null 2>&1; then
        READY=1
        break
    fi
    if ! kill -0 "$WORKER_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done
sleep 1
kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""

if [ "$READY" -ne 1 ]; then
    echo "Submitted worker did not produce 1000 records and a stats endpoint" >&2
    cat /tmp/verifier_worker.log >&2 2>/dev/null || true
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
from collections import defaultdict

import pytest
import requests

OUTPUT_FILE = "/home/user/etl_worker/output_clean.jsonl"
STATS_URL = "http://127.0.0.1:9090/stats"
MANIFEST_FILE = "/tmp/verifier_manifest.json"
SERVED_FILE = "/tmp/verifier_served.jsonl"
MONITOR_FILE = "/tmp/redis_monitor.log"


def get_stats():
    try:
        resp = requests.get(STATS_URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to stats endpoint at {STATS_URL}: {e}")
    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}"
    assert "application/json" in resp.headers.get("Content-Type", "").lower(), \
        f"Expected Content-Type: application/json, got {resp.headers.get('Content-Type')}"
    try:
        return resp.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {resp.text}")


def test_stats_endpoint_is_available_and_valid():
    stats = get_stats()
    assert "total_unique" in stats, "Missing 'total_unique' key in stats response"
    assert "averages" in stats, "Missing 'averages' key in stats response"
    assert "sample_count" in stats, "Missing 'sample_count' key in stats response"
    assert isinstance(stats["total_unique"], int), "'total_unique' must be an integer"
    assert stats["total_unique"] >= 1000, \
        f"Expected at least 1000 unique records processed, got {stats['total_unique']}"
    assert isinstance(stats["averages"], dict), "'averages' must be a dictionary"
    assert isinstance(stats["sample_count"], int), "'sample_count' must be an integer"


def test_output_file_contents_and_consistency():
    assert os.path.isfile(OUTPUT_FILE), \
        f"Output file {OUTPUT_FILE} does not exist. Did the worker write to the correct path?"
    stats = get_stats()
    total_unique_stat = stats["total_unique"]
    sample_count_stat = stats["sample_count"]
    averages_stat = stats["averages"]

    with open(MANIFEST_FILE, encoding="utf-8") as f:
        source_records = json.load(f)
    expected = {r["id"]: r for r in source_records}
    served_ids = set()
    with open(SERVED_FILE, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                served_ids.add(json.loads(line)["id"])

    seen_ids = set()
    sampled_count = 0
    category_sums = defaultdict(float)
    category_counts = defaultdict(int)
    sampled_by_category = defaultdict(int)
    line_count = 0

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            line_count += 1
            try:
                record = json.loads(line)
            except (ValueError, UnicodeError) as e:
                pytest.fail(f"Invalid JSON or UTF-8 on line {line_count} of output file: {e}")

            assert isinstance(record, dict), f"Record on line {line_count} is not a JSON object"
            for field in ("id", "text", "category", "value"):
                assert field in record, f"Missing '{field}' field in record on line {line_count}"
            assert isinstance(record["id"], str), f"'id' must be a string on line {line_count}"
            assert isinstance(record["text"], str), f"'text' must be a UTF-8 string on line {line_count}"
            assert isinstance(record["category"], str), f"'category' must be a string on line {line_count}"
            assert isinstance(record["value"], (int, float)) and not isinstance(record["value"], bool), \
                f"'value' must be numeric on line {line_count}"

            record_id = record["id"]
            assert record_id not in seen_ids, f"Duplicate id found in output: {record_id}. Deduplication failed."
            seen_ids.add(record_id)
            assert record_id in expected, f"Output id {record_id} was not supplied by the controlled upstream"
            assert record_id in served_ids, f"Output id {record_id} was never served over /stream"
            source = expected[record_id]
            assert record["text"] == source["text"], f"Text was corrupted for id {record_id}"
            assert record["category"] == source["category"], f"Category changed for id {record_id}"
            assert math.isclose(float(record["value"]), float(source["value"]), rel_tol=1e-12, abs_tol=1e-12), \
                f"Value changed for id {record_id}"

            cat = record["category"]
            val = float(record["value"])
            category_sums[cat] += val
            category_counts[cat] += 1
            if record.get("sampled") is True:
                sampled_count += 1
                sampled_by_category[cat] += 1

    assert line_count == total_unique_stat, \
        f"Output file has {line_count} lines, but stats endpoint reports {total_unique_stat} total_unique"
    assert sampled_count == sample_count_stat, \
        f"Output file has {sampled_count} sampled records, but stats endpoint reports {sample_count_stat}"
    assert line_count >= 1000, f"Expected at least 1000 output records, got {line_count}"
    assert seen_ids == set(expected), "Worker did not process exactly the 1000 unique upstream records"

    expected_sample = total_unique_stat * 0.1
    assert math.isclose(sampled_count, expected_sample, rel_tol=0.15, abs_tol=10), \
        f"Sample count {sampled_count} is not approximately 10% of total unique records ({total_unique_stat})"

    assert set(averages_stat) == set(category_counts), \
        "Stats averages do not contain exactly the upstream categories"
    for cat, count in category_counts.items():
        expected_avg = category_sums[cat] / count
        reported_avg = averages_stat.get(cat)
        assert reported_avg is not None, f"Missing average for category '{cat}' in stats endpoint"
        assert math.isclose(expected_avg, float(reported_avg), rel_tol=1e-3), \
            f"Average for category '{cat}' mismatch: expected {expected_avg}, but endpoint reported {reported_avg}"
        expected_cat_sample = count * 0.1
        actual_cat_sample = sampled_by_category[cat]
        assert math.isclose(actual_cat_sample, expected_cat_sample, rel_tol=0.20, abs_tol=3), \
            f"Category '{cat}' is not sampled at approximately 10%: {actual_cat_sample} of {count}"


def redis_repr(data):
    out = ''
    escapes = {10: r'\n', 13: r'\r', 9: r'\t', 7: r'\a', 8: r'\b'}
    for b in data:
        if b in escapes:
            out += escapes[b]
        elif b == 34:
            out += r'\"'
        elif b == 92:
            out += r'\\'
        elif 32 <= b <= 126:
            out += chr(b)
        else:
            out += r'\x%02x' % b
    return out


def test_redis_tracks_cryptographic_id_hashes():
    with open(MANIFEST_FILE, encoding="utf-8") as f:
        records = json.load(f)
    monitor = open(MONITOR_FILE, "r", encoding="utf-8", errors="replace").read()
    lower = monitor.lower()
    assert re.search(r'"(?:set|setnx|sadd|hset|hsetnx)"', lower), \
        "No Redis state-mutating command was observed while the worker processed records"

    matched = 0
    for record in records:
        raw = record["id"].encode("utf-8")
        digests = (hashlib.md5(raw).digest(), hashlib.sha1(raw).digest())
        forms = []
        for digest in digests:
            forms.extend((digest.hex(), redis_repr(digest)))
        if any(form.lower() in lower for form in forms):
            matched += 1
    assert matched >= 100, \
        f"Redis traffic contained MD5/SHA-1 hashes for only {matched} upstream ids; expected hash-based Redis deduplication"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
