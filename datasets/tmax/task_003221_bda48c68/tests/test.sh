#!/bin/bash
set -u
mkdir -p /logs/verifier

MOCK_PID=""
cleanup() {
    if [ -n "$MOCK_PID" ]; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Stop the originally configured Flask processes so verification can provide a
# controlled stream and independently record the submitted reports.
pkill -f '/home/user/services/config_api/app.py' 2>/dev/null || true
pkill -f '/home/user/services/receiver/app.py' 2>/dev/null || true
sleep 1
rm -f /home/user/processed_events.jsonl /tmp/reports.json

cat << 'SERVER_EOF' > /tmp/verifier_services.py
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = [
    {"event_id": "bad-high", "server_id": "srv2", "timestamp": 1600000105.0, "cpu_limit": 2.0, "mem_limit": 70000, "config_blob": "discard-high"},
    {"event_id": "2", "server_id": "srv1", "timestamp": 1600000010.0, "cpu_limit": 2.5, "mem_limit": 2048, "config_blob": "totally-different"},
    {"event_id": "s2-b", "server_id": "srv2", "timestamp": 1600000110.0, "cpu_limit": None, "mem_limit": None, "config_blob": "abcdefghik"},
    {"event_id": "s1-start", "server_id": "srv1", "timestamp": 1599999990.0, "cpu_limit": None, "mem_limit": 900, "config_blob": "edge-start"},
    {"event_id": "1", "server_id": "srv1", "timestamp": 1600000000.0, "cpu_limit": 2.0, "mem_limit": 1024, "config_blob": "configA"},
    {"event_id": "bad-negative", "server_id": "srv1", "timestamp": 1600000003.0, "cpu_limit": -1.0, "mem_limit": 1200, "config_blob": "discard-negative"},
    {"event_id": "s2-c", "server_id": "srv2", "timestamp": 1600000120.0, "cpu_limit": 3.0, "mem_limit": 1536, "config_blob": "ZZZZZZZZZZ"},
    {"event_id": "3", "server_id": "srv1", "timestamp": 1600000004.0, "cpu_limit": None, "mem_limit": None, "config_blob": "configA!"},
    {"event_id": "bad-low", "server_id": "srv1", "timestamp": 1600000002.0, "cpu_limit": 2.1, "mem_limit": 511, "config_blob": "discard-low"},
    {"event_id": "s2-a", "server_id": "srv2", "timestamp": 1600000100.0, "cpu_limit": 1.0, "mem_limit": 512, "config_blob": "abcdefghij"},
    {"event_id": "s1-end", "server_id": "srv1", "timestamp": 1600000020.0, "cpu_limit": 3.0, "mem_limit": None, "config_blob": "edge-end"},
]

class ReusableServer(ThreadingHTTPServer):
    allow_reuse_address = True

class StreamHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/stream':
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(EVENTS).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

class ReceiverHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/changelog':
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            payload = json.loads(self.rfile.read(length).decode())
            with open('/tmp/reports.json', 'a') as f:
                f.write(json.dumps(payload) + '\n')
            body = b'ok'
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass

stream = ReusableServer(('127.0.0.1', 5000), StreamHandler)
receiver = ReusableServer(('127.0.0.1', 5001), ReceiverHandler)
threading.Thread(target=stream.serve_forever, daemon=True).start()
receiver.serve_forever()
SERVER_EOF

python3 /tmp/verifier_services.py >/tmp/verifier_services.log 2>&1 &
MOCK_PID=$!

READY=0
for _ in $(seq 1 30); do
    if python3 - <<'PY' >/dev/null 2>&1
import urllib.request
with urllib.request.urlopen('http://127.0.0.1:5000/stream', timeout=1) as r:
    assert r.status == 200
PY
    then
        READY=1
        break
    fi
    sleep 0.2
done

PIPELINE_STATUS=1
if [ "$READY" -eq 1 ] && [ -f /home/user/pipeline.py ] && [ ! -L /home/user/pipeline.py ]; then
    timeout 30s python3 /home/user/pipeline.py >/tmp/pipeline-verifier.log 2>&1
    PIPELINE_STATUS=$?
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os


def read_jsonl(path):
    values = []
    with open(path, 'r') as f:
        for line in f:
            if line.strip():
                values.append(json.loads(line))
    return values


def test_pipeline_executed_successfully():
    assert int(os.environ['PIPELINE_STATUS']) == 0, 'pipeline.py did not execute successfully'
    assert os.path.isfile('/home/user/pipeline.py'), '/home/user/pipeline.py is missing or is not a regular file'
    assert not os.path.islink('/home/user/pipeline.py'), '/home/user/pipeline.py must be an implemented script, not a symlink'


def test_settings_fixed():
    settings_path = '/home/user/services/config_api/settings.env'
    assert os.path.exists(settings_path), f'{settings_path} does not exist'
    with open(settings_path, 'r') as f:
        content = f.read()
    # Preserve the original assertion and additionally ensure this is the active value.
    assert 'REDIS_URL=redis://127.0.0.1:6379' in content, 'REDIS_URL was not correctly fixed to port 6379 in settings.env'
    active = {}
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        active[key.strip()] = value.strip()
    assert active.get('REDIS_URL') == 'redis://127.0.0.1:6379'


def test_processed_events_exists():
    assert os.path.exists('/home/user/processed_events.jsonl'), '/home/user/processed_events.jsonl is missing'


def test_complete_processed_output():
    rows = read_jsonl('/home/user/processed_events.jsonl')
    assert rows, 'No processed events found in output file.'
    required = {'event_id', 'server_id', 'timestamp', 'cpu_limit', 'mem_limit', 'config_blob'}
    for row in rows:
        assert set(row) == required, f'Wrong fields for event {row.get("event_id")}: {set(row)}'

    ids = [row['event_id'] for row in rows]
    assert len(ids) == len(set(ids)), 'Duplicate event IDs were emitted'
    assert set(ids) == {'1', '2', '3', 's2-a', 's2-b', 's2-c'}, 'Output did not contain exactly all valid, imputable events'

    expected = {
        '1': ('srv1', 1600000000.0, 2.0, 1024.0, 'configA'),
        '3': ('srv1', 1600000004.0, 2.2, 1433.6, 'configA!'),
        '2': ('srv1', 1600000010.0, 2.5, 2048.0, 'totally-different'),
        's2-a': ('srv2', 1600000100.0, 1.0, 512.0, 'abcdefghij'),
        's2-b': ('srv2', 1600000110.0, 2.0, 1024.0, 'abcdefghik'),
        's2-c': ('srv2', 1600000120.0, 3.0, 1536.0, 'ZZZZZZZZZZ'),
    }
    by_id = {row['event_id']: row for row in rows}
    for eid, (server, timestamp, cpu, mem, blob) in expected.items():
        row = by_id[eid]
        assert row['server_id'] == server
        assert math.isclose(float(row['timestamp']), timestamp, rel_tol=0, abs_tol=1e-9)
        assert math.isclose(float(row['cpu_limit']), cpu, rel_tol=0, abs_tol=1e-9)
        assert math.isclose(float(row['mem_limit']), mem, rel_tol=0, abs_tol=1e-9)
        assert row['config_blob'] == blob

    for server in ('srv1', 'srv2'):
        timestamps = [float(row['timestamp']) for row in rows if row['server_id'] == server]
        assert timestamps == sorted(timestamps), f'Events for {server} are not ordered by timestamp'


def test_imputation_mse():
    ground_truth_path = '/var/opt/ground_truth.jsonl'
    processed_path = '/home/user/processed_events.jsonl'
    assert os.path.exists(ground_truth_path), f'{ground_truth_path} is missing'
    assert os.path.exists(processed_path), f'{processed_path} is missing'

    ground_truth = {ev['event_id']: ev for ev in read_jsonl(ground_truth_path)}
    processed = {ev['event_id']: ev for ev in read_jsonl(processed_path)}
    assert len(processed) > 0, 'No processed events found in output file.'

    sq_errors = []
    for eid, p_ev in processed.items():
        if eid in ground_truth:
            gt_ev = ground_truth[eid]
            for key in ('cpu_limit', 'mem_limit'):
                if p_ev.get(key) is not None and gt_ev.get(key) is not None:
                    sq_errors.append((float(p_ev[key]) - float(gt_ev[key])) ** 2)
    assert sq_errors, 'No matching events with numeric limits found for MSE calculation.'
    mse = sum(sq_errors) / len(sq_errors)
    assert mse < 0.5, f'Imputation MSE is {mse:.4f}, which is not strictly less than 0.5.'


def test_reports_sent_and_correct():
    reports_path = '/tmp/reports.json'
    assert os.path.exists(reports_path), 'Reports were not saved to /tmp/reports.json by the receiver app. Did you POST to the correct endpoint?'
    with open(reports_path, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, 'Reports file is empty. No valid payloads were received.'

    reports = [json.loads(line) for line in content.splitlines() if line.strip()]
    assert len(reports) == 2, 'Exactly one report per server must be posted'
    assert all(set(report) == {'server_id', 'report_markdown'} for report in reports), 'Report payload has incorrect fields'
    by_server = {report['server_id']: report['report_markdown'].rstrip('\n') for report in reports}
    assert set(by_server) == {'srv1', 'srv2'}

    expected = {
        'srv1': '# Server: srv1\nTotal valid events: 3\nAverage CPU Limit: 2.23\nAverage Mem Limit: 1501.87\nMajor Updates: 1\nMinor Tweaks: 1',
        'srv2': '# Server: srv2\nTotal valid events: 3\nAverage CPU Limit: 2.00\nAverage Mem Limit: 1024.00\nMajor Updates: 1\nMinor Tweaks: 1',
    }
    assert by_server == expected
TEST_EOF

if PIPELINE_STATUS="$PIPELINE_STATUS" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
