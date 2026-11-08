#!/bin/bash
set +e
mkdir -p /logs/verifier
RESULT=1
SERVER_PID=""
BACKUP_DIR=$(mktemp -d)

cp -a /home/user/data/. "$BACKUP_DIR/" 2>/dev/null

kill_listener() {
python3 <<'PY'
import os, signal, time
inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(path) as f:
            next(f)
            for line in f:
                cols = line.split()
                if cols[3] == '0A' and int(cols[1].split(':')[1], 16) == 5050:
                    inodes.add(cols[9])
    except OSError:
        pass
pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    kill_listener >/dev/null 2>&1
    rm -f /home/user/data/table_alpha.csv /home/user/data/table_beta.csv /home/user/data/table_gamma.csv
    cp -a "$BACKUP_DIR"/. /home/user/data/ 2>/dev/null
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

wait_for_server() {
    python3 - "$SERVER_PID" <<'PY'
import os, socket, sys, time
pid = int(sys.argv[1])
for _ in range(100):
    try:
        os.kill(pid, 0)
    except OSError:
        raise SystemExit(1)
    s = socket.socket()
    s.settimeout(0.15)
    try:
        s.connect(('127.0.0.1', 5050))
        s.close()
        raise SystemExit(0)
    except OSError:
        s.close()
        time.sleep(0.1)
raise SystemExit(1)
PY
}

start_server() {
    kill_listener >/dev/null 2>&1
    "$BIN" >/tmp/traffic-api-verifier.log 2>&1 &
    SERVER_PID=$!
    wait_for_server
}

stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
        SERVER_PID=""
    fi
    kill_listener >/dev/null 2>&1
}

if [ ! -f /home/user/traffic-api/Cargo.toml ] || [ ! -f /home/user/traffic-api/src/main.rs ]; then
    echo "Missing required Rust Cargo project" >&2
    RESULT=0
else
    cd /home/user/traffic-api || RESULT=0
    if ! timeout 180 cargo build --offline >/tmp/traffic-api-build.log 2>&1; then
        cat /tmp/traffic-api-build.log >&2
        RESULT=0
    fi
fi

if [ "$RESULT" -eq 1 ]; then
    BIN_NAME=$(cargo metadata --offline --no-deps --format-version=1 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); bins=[t["name"] for p in d["packages"] for t in p["targets"] if "bin" in t["kind"]]; print(bins[0] if len(bins)==1 else "")')
    BIN="/home/user/traffic-api/target/debug/$BIN_NAME"
    if [ -z "$BIN_NAME" ] || [ ! -f "$BIN" ] || [ ! -x "$BIN" ]; then
        echo "Cargo project does not produce exactly one executable binary" >&2
        RESULT=0
    fi
fi

cat <<'PYTEST' > /tmp/test_traffic_api.py
import csv
import os
import subprocess
import tempfile
from urllib.parse import quote

import requests

BASE_URL = "http://127.0.0.1:5050/highest-confidence-frame"
AUTH_HEADER = {"Authorization": "Bearer super-analyst-2024"}
VIDEO = "/app/footage.mp4"
WIDTH, HEIGHT = 640, 480


def expected_events():
    with open('/home/user/data/table_alpha.csv', newline='') as f:
        events = {r['event_id']: r['timestamp_sec'] for r in csv.DictReader(f)}
    with open('/home/user/data/table_beta.csv', newline='') as f:
        classes = {r['class_id']: r['category_name'] for r in csv.DictReader(f)}
    best = {}
    with open('/home/user/data/table_gamma.csv', newline='') as f:
        for row in csv.DictReader(f):
            category = classes[row['class_id']]
            candidate = (float(row['confidence']), events[row['event_id']])
            if category not in best or candidate[0] > best[category][0]:
                best[category] = candidate
    return {category: timestamp for category, (_, timestamp) in best.items()}


def raw_frame(timestamp):
    proc = subprocess.run([
        'ffmpeg', '-v', 'error', '-ss', format(timestamp, '.9f'), '-i', VIDEO,
        '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert proc.returncode == 0, proc.stderr.decode(errors='replace')
    assert len(proc.stdout) == WIDTH * HEIGHT * 3
    return proc.stdout


def decode_jpeg(body):
    with tempfile.NamedTemporaryFile(suffix='.jpg') as f:
        f.write(body)
        f.flush()
        proc = subprocess.run([
            'ffmpeg', '-v', 'error', '-i', f.name, '-frames:v', '1',
            '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert proc.returncode == 0, f"Response is not a decodable JPEG: {proc.stderr.decode(errors='replace')}"
    assert len(proc.stdout) == WIDTH * HEIGHT * 3, "JPEG has the wrong dimensions"
    return proc.stdout


def mse(a, b):
    return sum((x-y) * (x-y) for x, y in zip(a, b)) / len(a)


def assert_exact_video_frame(body, timestamp_text):
    assert body.startswith(b'\xff\xd8'), "Response body does not start with JPEG magic bytes (FF D8)"
    decoded = decode_jpeg(body)
    timestamp = float(timestamp_text)
    target_error = mse(decoded, raw_frame(timestamp))
    assert target_error < 225, f"JPEG does not depict the requested source frame (MSE {target_error:.2f})"

    # A valid JPEG of a nearby frame is not sufficient: the requested frame must
    # be the closest source frame after accounting for JPEG compression.
    competitors = []
    for delta in (-1/30, 1/30):
        other = timestamp + delta
        if 0 <= other < 10:
            competitors.append(mse(decoded, raw_frame(other)))
    assert all(target_error < error for error in competitors), \
        f"JPEG is not the exact frame at {timestamp_text}; errors={target_error, competitors}"


def request_and_check(category, expected_timestamp):
    try:
        resp = requests.get(BASE_URL, params={'category': category}, headers=AUTH_HEADER, timeout=15)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the server: {exc}"
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    assert resp.headers.get('Content-Type') == 'image/jpeg', \
        f"Expected Content-Type image/jpeg, got {resp.headers.get('Content-Type')}"
    assert resp.headers.get('X-Event-Timestamp') == expected_timestamp, \
        f"Expected X-Event-Timestamp {expected_timestamp}, got {resp.headers.get('X-Event-Timestamp')}"
    assert_exact_video_frame(resp.content, expected_timestamp)


def test_auth_missing():
    try:
        resp = requests.get(BASE_URL, params={'category': 'truck'}, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the server: {exc}"
    assert resp.status_code == 401, f"Expected 401 Unauthorized when missing auth, got {resp.status_code}"


def test_auth_invalid():
    try:
        resp = requests.get(BASE_URL, params={'category': 'truck'},
                            headers={'Authorization': 'Bearer wrong-token'}, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the server: {exc}"
    assert resp.status_code == 401, f"Expected 401 Unauthorized when invalid auth, got {resp.status_code}"


def test_expected_categories():
    expected = expected_events()
    phase = os.environ.get('VERIFY_PHASE')
    if phase == 'original':
        assert expected['truck'] == '5.1'
        assert expected['bicycle'] == '8.0'
        request_and_check('truck', '5.1')
        request_and_check('bicycle', '8.0')
    else:
        assert set(expected) == {'truck', 'bicycle', 'car'}
        for category, timestamp in expected.items():
            request_and_check(category, timestamp)
PYTEST

if [ "$RESULT" -eq 1 ]; then
    if ! start_server; then
        echo "Built Rust server failed to bind to 127.0.0.1:5050" >&2
        cat /tmp/traffic-api-verifier.log >&2
        RESULT=0
    elif ! VERIFY_PHASE=original python3 -m pytest /tmp/test_traffic_api.py -x --tb=short; then
        RESULT=0
    fi
    stop_server
fi

# Replace the input with a verifier-generated cross-query challenge, then restart
# the same submitted Rust binary so implementations that load CSVs at startup are valid.
if [ "$RESULT" -eq 1 ]; then
python3 <<'PY'
import csv, random, secrets
rng = random.Random(int.from_bytes(secrets.token_bytes(16), 'big'))
event_ids = rng.sample(range(1000, 9000), 5)
class_ids = rng.sample(range(100, 900), 3)
timestamps = rng.sample(['0.7','1.4','2.9','3.6','4.8','6.2','7.1','8.6','9.3'], 5)
categories = ['truck', 'bicycle', 'car']
rng.shuffle(categories)
with open('/home/user/data/table_alpha.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['event_id','timestamp_sec']); w.writerows(zip(event_ids, timestamps))
with open('/home/user/data/table_beta.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['class_id','category_name']); w.writerows(zip(class_ids, categories))
rows = [
    [event_ids[0], class_ids[0], '0.31'],
    [event_ids[1], class_ids[0], '0.97'],
    [event_ids[2], class_ids[1], '0.88'],
    [event_ids[3], class_ids[1], '0.42'],
    [event_ids[4], class_ids[2], '0.93'],
    [event_ids[0], class_ids[2], '0.27'],
]
rng.shuffle(rows)
with open('/home/user/data/table_gamma.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['event_id','class_id','confidence']); w.writerows(rows)
PY
    if ! start_server; then
        echo "Rust server failed after verifier-generated CSV challenge" >&2
        cat /tmp/traffic-api-verifier.log >&2
        RESULT=0
    elif ! VERIFY_PHASE=dynamic python3 -m pytest /tmp/test_traffic_api.py -x --tb=short; then
        RESULT=0
    fi
    stop_server
fi

if [ "$RESULT" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
