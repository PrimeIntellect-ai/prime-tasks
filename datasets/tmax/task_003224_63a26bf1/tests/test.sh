#!/bin/bash
set +e
mkdir -p /logs/verifier

ORIG_WAL="/tmp/store.wal.original.$$"
SERVICE_PID=""
cp /home/user/data/store.wal "$ORIG_WAL" 2>/dev/null

kill_listener() {
python3 - <<'PY'
import os, signal, time
port_hex = format(8888, '04X')
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        cols = line.split()
        if cols[1].split(':')[-1].upper() == port_hex and cols[3] == '0A':
            inodes.add(cols[9])
for pid in os.listdir('/proc'):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
time.sleep(0.3)
PY
}

stop_service() {
    if [ -n "$SERVICE_PID" ]; then
        kill "$SERVICE_PID" 2>/dev/null
        wait "$SERVICE_PID" 2>/dev/null
        SERVICE_PID=""
    fi
    kill_listener >/dev/null 2>&1
}

restore_state() {
    stop_service
    if [ -f "$ORIG_WAL" ]; then
        cp "$ORIG_WAL" /home/user/data/store.wal
        rm -f "$ORIG_WAL"
    fi
}
trap restore_state EXIT

start_service() {
    kill_listener || return 1
    cd /home/user/logd || return 1
    ./target/release/logd >/tmp/logd-verifier.log 2>&1 &
    SERVICE_PID=$!
    for _ in $(seq 1 40); do
        kill -0 "$SERVICE_PID" 2>/dev/null || return 1
        python3 - <<'PY' >/dev/null 2>&1 && return 0
import socket
s = socket.create_connection(('127.0.0.1', 8888), timeout=.2)
s.close()
PY
        sleep .1
    done
    return 1
}

run_checks() {
    python3 - <<'PY' || return 1
from pathlib import Path
import cv2

wal = Path('/home/user/logd/src/wal.rs')
main = Path('/home/user/logd/src/main.rs')
video = Path('/app/error_signal.mp4')
assert wal.is_file() and main.is_file() and video.is_file()
assert not wal.is_symlink() and not main.is_symlink()

cap = cv2.VideoCapture(str(video))
bits = []
while True:
    ok, frame = cap.read()
    if not ok:
        break
    bits.append('1' if float(frame[:50, :50].mean()) > 127 else '0')
cap.release()
assert len(bits) == 16, f'expected 16 video frames, got {len(bits)}'
seed = int(''.join(bits), 2)
assert 0 <= seed <= 0xffff

wal_src = wal.read_text()
main_src = main.read_text()
assert 'pub fn load_wal' in wal_src
assert '^' in wal_src, 'wal.rs does not perform XOR recovery'
assert 'read_exact(&mut payload).unwrap()' not in wal_src, 'payload truncation still panics'
assert 'mod wal' in main_src and 'wal::load_wal' in main_src
compact = ''.join(main_src.split())
assert 'socket.read(&mutbuf).await.unwrap()' not in compact, 'disconnect read is still unhandled'
assert 'socket.write_all(res.as_bytes()).await.unwrap()' not in compact, 'disconnect write is still unhandled'
PY

    cd /home/user/logd || return 1
    cargo build --release || return 1
    test -x /home/user/logd/target/release/logd || return 1

    cp "$ORIG_WAL" /home/user/data/store.wal || return 1
    start_service || return 1

    # Preserve the original verifier's four assertions.
    python3 - <<'PY' || return 1
import requests
base = 'http://127.0.0.1:8888/record/'
for rid, status, body in [
    (1, 200, 'SYSTEM_STARTUP'),
    (2, 200, 'USER_LOGIN_SUCCESS'),
    (3, 404, None),
    (4, 200, 'CRITICAL_SYSTEM_RECOVERED'),
]:
    r = requests.get(base + str(rid), timeout=2)
    assert r.status_code == status, (rid, r.status_code)
    if body is not None:
        assert r.text.strip() == body, (rid, r.text)
PY

    stop_service

    # Build a fresh WAL with unpredictable IDs and plaintext. Expected answers are
    # derived from the video seed, so a fixed-response HTTP server cannot pass.
    python3 - <<'PY' || return 1
import cv2, json, os, secrets, struct, string
cap = cv2.VideoCapture('/app/error_signal.mp4')
bits = []
while True:
    ok, frame = cap.read()
    if not ok:
        break
    bits.append(1 if float(frame[:50, :50].mean()) > 127 else 0)
cap.release()
assert len(bits) == 16
seed = 0
for bit in bits:
    seed = (seed << 1) | bit
key = seed.to_bytes(2, 'big')
alphabet = string.ascii_letters + string.digits + '_-'
records = {}
while len(records) < 6:
    rid = secrets.randbelow(2**31 - 1000) + 1000
    records.setdefault(rid, ''.join(secrets.choice(alphabet) for _ in range(18 + len(records))))
with open('/home/user/data/store.wal', 'wb') as f:
    for rid, text in records.items():
        raw = text.encode()
        payload = bytes(b ^ key[i % 2] for i, b in enumerate(raw))
        f.write(struct.pack('<II', rid, len(payload)))
        f.write(payload)
    bad_id = secrets.randbelow(2**31 - 1000) + 1000
    while bad_id in records:
        bad_id = secrets.randbelow(2**31 - 1000) + 1000
    f.write(struct.pack('<II', bad_id, 100) + os.urandom(4))
with open('/tmp/logd-dynamic.json', 'w') as f:
    json.dump({'records': records, 'bad_id': bad_id}, f)
PY

    start_service || return 1

    python3 - <<'PY' || return 1
import json, requests, socket, time
with open('/tmp/logd-dynamic.json') as f:
    data = json.load(f)
base = 'http://127.0.0.1:8888/record/'
for rid, expected in data['records'].items():
    r = requests.get(base + rid, timeout=2)
    assert r.status_code == 200, (rid, r.status_code)
    assert r.text.strip() == expected, (rid, r.text, expected)
r = requests.get(base + str(data['bad_id']), timeout=2)
assert r.status_code == 404
r = requests.get(base + '4294967295', timeout=2)
assert r.status_code == 404

# Exercise abrupt client disconnects, then ensure the same process still serves data.
for _ in range(500):
    s = socket.create_connection(('127.0.0.1', 8888), timeout=1)
    s.close()
time.sleep(.3)
rid, expected = next(iter(data['records'].items()))
r = requests.get(base + rid, timeout=2)
assert r.status_code == 200 and r.text.strip() == expected
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
