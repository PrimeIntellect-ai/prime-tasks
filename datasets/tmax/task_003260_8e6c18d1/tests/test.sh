#!/bin/bash
set +e
mkdir -p /logs/verifier

REAL_TOOL=/app/cpk_tool.verifier-real
MARKER=/home/user/.cpk_tool_verifier_calls
rm -f "$REAL_TOOL" "$MARKER"
touch "$MARKER"
chmod 666 "$MARKER"

cp /app/cpk_tool "$REAL_TOOL"
chmod 755 "$REAL_TOOL"
cat > /tmp/cpk_tool.wrapper <<'WRAP_EOF'
#!/usr/bin/python3
import hashlib
import subprocess
import sys

data = sys.stdin.buffer.read()
try:
    with open('/home/user/.cpk_tool_verifier_calls', 'a') as f:
        f.write(hashlib.sha256(data).hexdigest() + '\n')
except Exception:
    pass
p = subprocess.run(['/app/cpk_tool.verifier-real'] + sys.argv[1:], input=data,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
WRAP_EOF
chmod 755 /tmp/cpk_tool.wrapper
mv /tmp/cpk_tool.wrapper /app/cpk_tool

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import secrets
import struct
import time
import zlib

import pytest
import requests

BASE_URL = "http://127.0.0.1:8181"
HEADERS = {"Authorization": "Bearer conf-sync-secret"}
SPOOL = "/home/user/spool"
CALL_LOG = "/home/user/.cpk_tool_verifier_calls"


def create_cpk(text_payload: str, timestamp: int) -> bytes:
    magic = b"CPK\x01"
    compressed = zlib.compress(text_payload.encode("utf-8"))
    payload_len = len(compressed)
    crc = zlib.crc32(compressed) & 0xFFFFFFFF
    header = struct.pack("<4sIII", magic, timestamp, payload_len, crc)
    return header + compressed


def get_latest():
    response = requests.get(f"{BASE_URL}/latest", headers=HEADERS, timeout=5)
    assert response.status_code == 200, f"GET /latest failed: {response.status_code} {response.text}"
    return response.json()


def wait_for_latest(timestamp, payload, timeout=12):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = get_latest()
            if last.get("status") == "ok" and last.get("timestamp") == timestamp and last.get("data") == payload:
                return last
        except (requests.RequestException, ValueError, AssertionError):
            pass
        time.sleep(0.2)
    pytest.fail(f"Latest did not become timestamp={timestamp}, data={payload!r}; last response was {last!r}")


def wait_for_tool_call(blob, timeout=8):
    wanted = hashlib.sha256(blob).hexdigest()
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(CALL_LOG) as f:
                if wanted in {line.strip() for line in f}:
                    return
        except OSError:
            pass
        time.sleep(0.1)
    pytest.fail("The service did not pipe the tested archive through /app/cpk_tool")


def atomic_spool(name, blob):
    temporary = os.path.join(SPOOL, name + ".writing")
    final = os.path.join(SPOOL, name + ".cpk")
    with open(temporary, "wb") as f:
        f.write(blob)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, final)
    return final


def test_service_ready_log():
    log_path = "/home/user/service_ready.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. Service might not be started."
    with open(log_path, "r") as f:
        content = f.read()
    assert "SERVICE RUNNING" in content, f"Log file {log_path} does not contain 'SERVICE RUNNING'."


def test_bound_exactly_to_loopback():
    listeners = []
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port = fields[1].split(":")
            if int(port, 16) == 8181 and fields[3] == "0A":
                listeners.append(address)
    assert "0100007F" in listeners, "No IPv4 listener bound to 127.0.0.1:8181"
    assert "00000000" not in listeners, "Service is listening on all IPv4 interfaces instead of exactly 127.0.0.1"


def test_api_unauthorized():
    url = "http://127.0.0.1:8181/latest"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API on 127.0.0.1:8181: {e}")
    assert response.status_code in (401, 403), f"Expected 401 or 403 for unauthorized request, got {response.status_code}"

    upload_response = requests.post(f"{BASE_URL}/upload", data=b"unauthorized", timeout=2)
    assert upload_response.status_code in (401, 403), "POST /upload did not require authorization"


def test_api_upload_and_latest():
    ts1 = int(time.time()) - 1000
    text1 = "config_data_version_1"
    cpk1 = create_cpk(text1, ts1)

    upload_res1 = requests.post(f"{BASE_URL}/upload", headers=HEADERS, data=cpk1, timeout=5)
    assert upload_res1.status_code == 200, f"Upload failed: {upload_res1.status_code} {upload_res1.text}"
    time.sleep(1)

    latest_res1 = requests.get(f"{BASE_URL}/latest", headers=HEADERS, timeout=5)
    assert latest_res1.status_code == 200, f"GET /latest failed: {latest_res1.status_code} {latest_res1.text}"
    data1 = latest_res1.json()
    assert data1.get("status") == "ok", "Expected status 'ok'"
    assert data1.get("timestamp") == ts1, f"Expected timestamp {ts1}, got {data1.get('timestamp')}"
    assert data1.get("data") == text1, f"Expected data '{text1}', got '{data1.get('data')}'"

    ts2 = ts1 + 500
    text2 = "config_data_version_2_updated"
    cpk2 = create_cpk(text2, ts2)

    upload_res2 = requests.post(f"{BASE_URL}/upload", headers=HEADERS, data=cpk2, timeout=5)
    assert upload_res2.status_code == 200, f"Upload failed: {upload_res2.status_code} {upload_res2.text}"
    time.sleep(1)

    latest_res2 = requests.get(f"{BASE_URL}/latest", headers=HEADERS, timeout=5)
    assert latest_res2.status_code == 200, f"GET /latest failed: {latest_res2.status_code} {latest_res2.text}"
    data2 = latest_res2.json()
    assert data2.get("timestamp") == ts2, f"Expected updated timestamp {ts2}, got {data2.get('timestamp')}"
    assert data2.get("data") == text2, f"Expected updated data '{text2}', got '{data2.get('data')}'"


def test_upload_is_saved_as_a_new_spool_file():
    token = secrets.token_hex(18)
    timestamp = 3000000000
    payload = f"uploaded-random-{token}"
    blob = create_cpk(payload, timestamp)
    before = set(glob.glob(os.path.join(SPOOL, "*.cpk")))

    response = requests.post(f"{BASE_URL}/upload", headers=HEADERS, data=blob, timeout=5)
    assert response.status_code == 200
    assert response.json().get("status") == "saved"

    deadline = time.time() + 5
    matching = []
    while time.time() < deadline:
        after = set(glob.glob(os.path.join(SPOOL, "*.cpk")))
        matching = []
        for path in after - before:
            try:
                if os.path.isfile(path) and open(path, "rb").read() == blob:
                    matching.append(path)
            except OSError:
                pass
        if matching:
            break
        time.sleep(0.1)
    assert matching, "POST /upload did not safely create a new .cpk file containing the request body in the spool"
    wait_for_latest(timestamp, payload)
    wait_for_tool_call(blob)


def test_external_watcher_timestamp_order_corruption_and_locking():
    token = secrets.token_hex(20)
    older_ts = 4294966000
    newer_ts = 4294966500
    partial_ts = 4294967000

    older_payload = f"external-older-{token}"
    newer_payload = f"external-newer-{token}"
    older_blob = create_cpk(older_payload, older_ts)
    newer_blob = create_cpk(newer_payload, newer_ts)

    # The newer timestamp arrives first; the later filesystem event is older.
    atomic_spool(f"verifier-newer-{token}", newer_blob)
    wait_for_latest(newer_ts, newer_payload)
    atomic_spool(f"verifier-older-{token}", older_blob)
    time.sleep(1.0)
    latest = get_latest()
    assert latest.get("timestamp") == newer_ts and latest.get("data") == newer_payload, \
        "Latest was selected by arrival/filename rather than embedded timestamp"
    wait_for_tool_call(newer_blob)
    wait_for_tool_call(older_blob)

    # A syntactically plausible archive with the maximum timestamp but a bad CRC
    # must be rejected by cpk_tool and must not replace the current configuration.
    bad = bytearray(create_cpk(f"corrupt-{token}", 4294967295))
    bad[12:16] = struct.pack("<I", (struct.unpack("<I", bad[12:16])[0] ^ 0xA5A5A5A5) & 0xFFFFFFFF)
    bad = bytes(bad)
    atomic_spool(f"verifier-corrupt-{token}", bad)
    wait_for_tool_call(bad)
    time.sleep(0.6)
    latest = get_latest()
    assert latest.get("timestamp") == newer_ts and latest.get("data") == newer_payload, \
        "A corrupt archive replaced the latest valid configuration"

    # Expose a .cpk filename while its writer remains open. It must not be
    # accepted in partial form, and it must be retried/processed after completion.
    partial_payload = f"completed-after-slow-write-{token}"
    partial_blob = create_cpk(partial_payload, partial_ts)
    partial_path = os.path.join(SPOOL, f"verifier-slow-{token}.cpk")
    with open(partial_path, "wb") as f:
        split = max(10, len(partial_blob) // 2)
        f.write(partial_blob[:split])
        f.flush()
        os.fsync(f.fileno())
        time.sleep(1.2)
        during = get_latest()
        assert during.get("timestamp") == newer_ts and during.get("data") == newer_payload, \
            "The watcher consumed a .cpk file while it was still being written"
        f.write(partial_blob[split:])
        f.flush()
        os.fsync(f.fileno())

    wait_for_latest(partial_ts, partial_payload, timeout=15)
    wait_for_tool_call(partial_blob)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?

if [ -f "$REAL_TOOL" ]; then
    cp "$REAL_TOOL" /app/cpk_tool
    chmod 755 /app/cpk_tool
    rm -f "$REAL_TOOL"
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
