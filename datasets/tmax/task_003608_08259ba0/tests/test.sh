#!/bin/bash
mkdir -p /logs/verifier

REAL=/app/storage_decode.verifier-real
MARKER=/tmp/storage_decode_invocations
rm -f "$REAL" "$MARKER"

if ! mv /app/storage_decode "$REAL"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

restore_decoder() {
    rm -f /app/storage_decode
    if [ -e "$REAL" ]; then
        mv "$REAL" /app/storage_decode
    fi
}
trap restore_decoder EXIT

cat > /app/storage_decode <<'WRAPPER_EOF'
#!/usr/bin/env python3
import hashlib
import os
import subprocess
import sys

data = sys.stdin.buffer.read()
record = (hashlib.sha256(data).hexdigest() + "\n").encode("ascii")
fd = os.open("/tmp/storage_decode_invocations", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
try:
    os.write(fd, record)
finally:
    os.close(fd)

proc = subprocess.run(["/app/storage_decode.verifier-real"], input=data, stdout=subprocess.PIPE)
sys.stdout.buffer.write(proc.stdout)
sys.exit(proc.returncode)
WRAPPER_EOF
chmod 755 /app/storage_decode
touch "$MARKER"
chmod 666 "$MARKER"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import hashlib
import json
import os
import random
import re
import struct
import time
import uuid

import pytest
import requests

URL = "http://127.0.0.1:9090/api/v1/inspect"
AUDIT = "/home/user/audit.csv"
MARKER = "/tmp/storage_decode_invocations"


def audit_bytes():
    if not os.path.exists(AUDIT):
        return b""
    with open(AUDIT, "rb") as f:
        return f.read()


def assert_new_audit_entry(before, volume, expected, started, ended):
    after = audit_bytes()
    assert after.startswith(before), "Audit log was overwritten instead of atomically appended"
    delta = after[len(before):].decode("utf-8")
    lines = [x for x in delta.splitlines() if x]
    if not before:
        assert lines and lines[0] == "timestamp,volume,usage_percent"
        lines = lines[1:]
    matches = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 3, f"Corrupt audit row: {line!r}"
        try:
            ts = int(parts[0])
            pct = float(parts[2])
        except ValueError:
            pytest.fail(f"Invalid timestamp or percentage in audit row: {line!r}")
        if parts[1] == volume and abs(pct - expected) < 0.01:
            matches.append(ts)
    assert matches, f"Request did not append an audit entry for {volume}"
    assert any(int(started) - 2 <= ts <= int(ended) + 2 for ts in matches), "Audit timestamp is not the request time"


def post_and_check(path, volume, expected):
    before = audit_bytes()
    started = time.time()
    try:
        resp = requests.post(URL, json={"filepath": path}, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    ended = time.time()
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert set(data.keys()) == {"volume", "usage_percent"}, f"Unexpected response shape: {data}"
    assert data.get("volume") == volume, f"Expected volume {volume!r}, got {data.get('volume')!r}"
    usage = data.get("usage_percent")
    assert usage is not None, "Missing 'usage_percent' in response"
    assert abs(float(usage) - expected) < 0.01, f"Expected usage_percent ~{expected}, got {usage}"
    assert_new_audit_entry(before, volume, expected, started, ended)


def test_api_snap1():
    post_and_check("/home/user/spool/snap1.enc", "vol-X1", 25.0)


def test_api_snap2():
    post_and_check("/home/user/spool/snap2.enc", "vol-Y2", 50.0)


def test_audit_log():
    audit_file = "/home/user/audit.csv"
    assert os.path.exists(audit_file), f"Audit log {audit_file} does not exist. Did the service create it?"

    with open(audit_file, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]

    assert len(lines) >= 3, "Audit log should have a header and at least 2 entries (from the tests just run)"
    assert lines[0] == "timestamp,volume,usage_percent", f"Incorrect header in audit.csv: {lines[0]}"

    found_snap1 = False
    found_snap2 = False

    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) == 3:
            vol = parts[1]
            pct = parts[2]
            if vol == "vol-X1" and (pct.startswith("25.") or pct == "25"):
                found_snap1 = True
            if vol == "vol-Y2" and (pct.startswith("50.") or pct == "50"):
                found_snap2 = True

    assert found_snap1, "Audit log missing entry for vol-X1 with ~25% usage"
    assert found_snap2, "Audit log missing entry for vol-Y2 with ~50% usage"


def make_fixture(path, volume, used, free):
    payload = json.dumps({
        "volume_id": volume,
        "used_bytes": used,
        "free_bytes": free,
        "inode_usage": 0.37,
    }, separators=(",", ":")).encode("utf-8")
    decoded = struct.pack(">II", 0xDEADC0DE, len(payload)) + payload
    encoded = bytes(b ^ 0x55 for b in decoded)
    with open(path, "wb") as f:
        f.write(encoded)
    os.chmod(path, 0o666)
    return encoded


def test_randomized_concurrent_requests_use_decoder_and_append_atomically():
    rng = random.SystemRandom()
    fixtures = []
    for i in range(24):
        volume = "vol-" + uuid.uuid4().hex[:12]
        while True:
            used = rng.randrange(1000, 9000000)
            free = rng.randrange(1000, 9000000)
            raw = used * 100.0 / (used + free)
            # Avoid an ambiguous exact half-cent rounding case.
            if abs((raw * 100) % 1 - 0.5) > 0.001:
                break
        expected = float(f"{raw:.2f}")
        path = f"/home/user/spool/verifier_{uuid.uuid4().hex}.enc"
        encoded = make_fixture(path, volume, used, free)
        fixtures.append((path, volume, expected, hashlib.sha256(encoded).hexdigest()))

    before = audit_bytes()
    assert before.startswith(b"timestamp,volume,usage_percent\n"), "Audit header is missing or malformed"
    with open(MARKER, "w"):
        pass

    started = time.time()
    def invoke(item):
        path, volume, expected, _ = item
        resp = requests.post(URL, json={"filepath": path}, timeout=15)
        return item, resp

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(invoke, fixtures))
    ended = time.time()

    for (path, volume, expected, _), resp in results:
        assert resp.status_code == 200, f"Request for {path} failed: {resp.status_code} {resp.text}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")
        assert set(data.keys()) == {"volume", "usage_percent"}, f"Unexpected response shape: {data}"
        assert data["volume"] == volume
        assert abs(float(data["usage_percent"]) - expected) < 0.01

    after = audit_bytes()
    assert after.startswith(before), "Concurrent requests overwrote or corrupted existing audit data"
    delta = after[len(before):].decode("utf-8")
    rows = [line for line in delta.splitlines() if line]
    assert len(rows) == len(fixtures), f"Expected one atomic audit append per successful request, got {len(rows)} rows"

    seen = {}
    for row in rows:
        parts = row.split(",")
        assert len(parts) == 3, f"Concurrent append produced a corrupt CSV row: {row!r}"
        assert re.fullmatch(r"[0-9]+", parts[0]), f"Invalid Unix timestamp: {parts[0]!r}"
        ts = int(parts[0])
        assert int(started) - 2 <= ts <= int(ended) + 2, f"Audit timestamp outside request interval: {ts}"
        try:
            pct = float(parts[2])
        except ValueError:
            pytest.fail(f"Invalid usage percentage in row: {row!r}")
        assert parts[1] not in seen, f"Duplicate audit entry for {parts[1]}"
        seen[parts[1]] = pct

    for _, volume, expected, _ in fixtures:
        assert volume in seen, f"Missing audit entry for {volume}"
        assert abs(seen[volume] - expected) < 0.01

    with open(MARKER, "r") as f:
        invoked_hashes = [line.strip() for line in f if line.strip()]
    for _, _, _, digest in fixtures:
        assert digest in invoked_hashes, "A requested file's exact bytes were not passed to /app/storage_decode"

    for path, _, _, _ in fixtures:
        os.unlink(path)


def test_invalid_decoded_format_is_not_successful_or_logged():
    path = f"/home/user/spool/verifier_bad_{uuid.uuid4().hex}.enc"
    bad_decoded = struct.pack(">II", 0x12345678, 2) + b"{}"
    with open(path, "wb") as f:
        f.write(bytes(b ^ 0x55 for b in bad_decoded))
    os.chmod(path, 0o666)
    before = audit_bytes()
    resp = requests.post(URL, json={"filepath": path}, timeout=10)
    assert resp.status_code != 200, "Invalid magic number must not be reported as a successful inspection"
    assert audit_bytes() == before, "A failed decode must not create a successful-query audit row"
    os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
