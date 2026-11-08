#!/bin/bash
set -e
mkdir -p /logs/verifier

cleanup() {
    if [ -n "${MOCK_PID:-}" ]; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Stop the unusable placeholder services and the submitted daemon so the daemon
# can be exercised against deterministic implementations of the documented API.
pkill -f '[e]tl_daemon.py' 2>/dev/null || true
pkill -f '[e]mitter.py' 2>/dev/null || true
pkill -f '[s]ink.py' 2>/dev/null || true
sleep 1

redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
redis-cli FLUSHALL >/dev/null
rm -f /tmp/mock_sink_records.jsonl /tmp/mock_expected.json /home/user/pipeline.log

cat << 'MOCK_EOF' > /tmp/mock_services.py
import json
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

base = datetime.now(timezone.utc).replace(microsecond=0)
def ts(minutes):
    return (base + timedelta(minutes=minutes)).isoformat().replace('+00:00', 'Z')

id1, id2, id3, id4 = [str(uuid.uuid4()) for _ in range(4)]
records = [
    {"id": id1, "timestamp": ts(0), "host": "host-a", "cpu_usage": 20.0},
    {"id": id1, "timestamp": ts(0), "host": "host-a", "cpu_usage": 20.0},
    {"id": id2, "timestamp": ts(2), "host": "host-a", "cpu_usage": 40.0},
    {"id": id3, "timestamp": ts(6), "host": "host-a", "cpu_usage": 100.0},
    {"id": id4, "timestamp": ts(3), "host": "host-b", "cpu_usage": 10.0},
    {"id": "not-a-uuid", "timestamp": ts(3), "host": "host-a", "cpu_usage": 50.0},
    {"id": str(uuid.uuid4()), "timestamp": "not-a-time", "host": "host-a", "cpu_usage": 50.0},
    {"id": str(uuid.uuid4()), "timestamp": ts(3), "host": "host a", "cpu_usage": 50.0},
    {"id": str(uuid.uuid4()), "timestamp": ts(3), "host": "host-a", "cpu_usage": 101.0},
]
with open('/tmp/mock_expected.json', 'w') as f:
    json.dump({
        "host-a": [
            {"timestamp": ts(0), "avg": 20.0},
            {"timestamp": ts(2), "avg": 30.0},
            {"timestamp": ts(6), "avg": 70.0},
        ],
        "host-b": [{"timestamp": ts(3), "avg": 10.0}],
    }, f)

class Emitter(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/metrics':
            self.send_response(404); self.end_headers(); return
        body = json.dumps(records).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

class Sink(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/aggregate':
            self.send_response(404); self.end_headers(); return
        try:
            n = int(self.headers.get('Content-Length', '0'))
            payload = json.loads(self.rfile.read(n))
            with open('/tmp/mock_sink_records.jsonl', 'a') as f:
                f.write(json.dumps(payload) + '\n')
            self.send_response(200)
            self.end_headers()
        except Exception:
            self.send_response(400)
            self.end_headers()
    def log_message(self, *args):
        pass

emitter = ThreadingHTTPServer(('127.0.0.1', 8080), Emitter)
sink = ThreadingHTTPServer(('127.0.0.1', 9090), Sink)
Thread(target=emitter.serve_forever, daemon=True).start()
sink.serve_forever()
MOCK_EOF

python3 /tmp/mock_services.py &
MOCK_PID=$!

python3 - <<'PY'
import time, urllib.request
for port, path in ((8080, '/metrics'),):
    deadline = time.time() + 10
    while True:
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}', timeout=1) as r:
                if r.status == 200:
                    break
        except Exception:
            if time.time() >= deadline:
                raise
            time.sleep(0.1)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import tempfile
import time
import uuid

SANITIZER = '/home/user/sanitizer.py'
DAEMON = '/home/user/etl_daemon.py'
READY = '/home/user/ready.flag'


def run_sanitizer(lines):
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, 'input.jsonl')
        dst = os.path.join(d, 'output.jsonl')
        with open(src, 'w') as f:
            for line in lines:
                f.write(line if isinstance(line, str) else json.dumps(line))
                f.write('\n')
        result = subprocess.run(
            ['python3', SANITIZER, src, dst], capture_output=True,
            text=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert os.path.exists(dst), 'Sanitizer did not create the output file'
        with open(dst) as f:
            return [json.loads(line) for line in f if line.strip()]


def test_required_artifacts_and_ready_flag():
    assert os.path.isfile(SANITIZER), 'sanitizer.py is missing'
    assert os.path.isfile(DAEMON), 'etl_daemon.py is missing'
    assert os.path.exists(READY), 'ready.flag is missing'


def test_sanitizer_accepts_valid_and_drops_every_invalid_record():
    good_ids = [str(uuid.uuid4()) for _ in range(3)]
    valid = [
        {"id": good_ids[0], "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": 0},
        {"id": good_ids[1], "timestamp": "2026-01-01T01:02:03+02:00", "host": "ABC-123", "cpu_usage": 50.5},
        {"id": good_ids[2], "timestamp": "2026-01-01T23:59:59Z", "host": "x", "cpu_usage": 100.0},
    ]
    invalid = [
        '{broken json',
        json.dumps({"id": "550e8400-e29b-11d4-a716-446655440000", "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": 1}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "not-iso8601", "host": "host-1", "cpu_usage": 1}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host 1", "cpu_usage": 1}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host;rm", "cpu_usage": 1}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": -0.01}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": 100.01}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": "50"}),
        json.dumps({"id": str(uuid.uuid4()), "timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": True}),
        json.dumps({"timestamp": "2026-01-01T00:00:00Z", "host": "host-1", "cpu_usage": 1}),
        '[]',
        'null',
    ]
    output = run_sanitizer([json.dumps(valid[0]), invalid[0], json.dumps(valid[1])] + invalid[1:] + [json.dumps(valid[2])])
    assert [r.get('id') for r in output] == good_ids


def test_bundled_invalid_corpora_are_dropped():
    # Both bundled records violate the instructed schema, including the record
    # formerly mislabeled as clean (id "123").
    for path in ('/app/data/corpus_clean/test.jsonl', '/app/data/corpus_evil/test.jsonl'):
        with open(path) as f:
            output = run_sanitizer([line.rstrip('\n') for line in f])
        assert output == [], f'{path} contains no valid UUIDv4 record and must be dropped'


def test_daemon_deduplicates_sanitizes_rolls_and_loads():
    proc = subprocess.Popen(['python3', DAEMON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 12
        while time.time() < deadline:
            if proc.poll() is not None:
                raise AssertionError('etl_daemon.py exited instead of running continuously')
            try:
                with open('/tmp/mock_sink_records.jsonl') as f:
                    count = sum(1 for line in f if line.strip())
            except FileNotFoundError:
                count = 0
            if count >= 4:
                break
            time.sleep(0.2)
        assert count >= 4, f'Only {count} aggregates were forwarded'

        # The emitter repeats the same batch. No additional posts may be made.
        time.sleep(2.5)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)

    with open('/tmp/mock_sink_records.jsonl') as f:
        posted = [json.loads(line) for line in f if line.strip()]
    assert len(posted) == 4, f'Expected four unique valid records, got {len(posted)} posts'

    with open('/tmp/mock_expected.json') as f:
        expected = json.load(f)
    by_host = {'host-a': [], 'host-b': []}
    for payload in posted:
        assert set(payload) == {'host', 'timestamp', 'avg_cpu_5m'}
        assert payload['host'] in by_host
        assert isinstance(payload['avg_cpu_5m'], (int, float)) and not isinstance(payload['avg_cpu_5m'], bool)
        assert math.isfinite(payload['avg_cpu_5m'])
        by_host[payload['host']].append(payload)

    for host, wanted in expected.items():
        got = by_host[host]
        assert len(got) == len(wanted)
        for actual, exp in zip(got, wanted):
            assert actual['timestamp'] == exp['timestamp']
            assert actual['avg_cpu_5m'] == pytest.approx(exp['avg'])

    assert os.path.isfile('/home/user/pipeline.log')
    with open('/home/user/pipeline.log', errors='replace') as f:
        log = f.read().lower()
    assert log.strip(), 'pipeline.log is empty'
    for term in ('poll', 'drop', 'dedup', 'forward'):
        assert re.search(term, log), f'pipeline.log does not track {term} counts'


import pytest
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
