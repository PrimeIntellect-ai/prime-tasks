#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_DECODER=/app/sensor_decoder.verifier-real
CALL_LOG=/tmp/sensor_decoder_verifier_calls
rm -f "$REAL_DECODER" "$CALL_LOG"
mv /app/sensor_decoder "$REAL_DECODER"
: > "$CALL_LOG"
chmod 666 "$CALL_LOG"

cat << 'WRAPPER_EOF' > /app/sensor_decoder
#!/bin/bash
tmp=$(mktemp /tmp/sensor-decoder-input.XXXXXX) || exit 1
cat > "$tmp"
hash=$(sha256sum "$tmp" | awk '{print $1}')
size=$(wc -c < "$tmp")
printf '%s %s\n' "$hash" "$size" >> /tmp/sensor_decoder_verifier_calls
/app/sensor_decoder.verifier-real < "$tmp"
rc=$?
rm -f "$tmp"
exit "$rc"
WRAPPER_EOF
chmod 755 /app/sensor_decoder

cleanup() {
    rm -f /app/sensor_decoder
    if [ -e "$REAL_DECODER" ]; then
        mv "$REAL_DECODER" /app/sensor_decoder
    fi
    rm -f "$CALL_LOG"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import struct
import time
import random
import re
import requests
import pytest
import hashlib
import unicodedata

URL = "http://127.0.0.1:9090/process"
GOOD_HEADERS = {"Authorization": "Bearer secr3t_t0k3n"}
CALL_LOG = "/tmp/sensor_decoder_verifier_calls"
SERVER_LOG = "/home/user/server.log"


def pack_record(t, val, user, text):
    """Pack a record into the custom binary format."""
    b_t = struct.pack('<I', t)
    b_val = struct.pack('<f', val) if val is not None else struct.pack('<f', float('nan'))
    b_user = user.encode('utf-8').ljust(16, b'\x00')[:16]
    b_text = text.encode('utf-8') + b'\x00'
    return b_t + b_val + b_user + b_text


def wait_for_decoder_call(payload, previous_size=0):
    expected = hashlib.sha256(payload).hexdigest()
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            with open(CALL_LOG, 'r', encoding='utf-8') as f:
                f.seek(previous_size)
                if expected in f.read().split():
                    return
        except OSError:
            pass
        time.sleep(0.05)
    pytest.fail("The request body was not passed through /app/sensor_decoder")


def read_log():
    try:
        with open(SERVER_LOG, 'r', encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ""


def wait_for_logged_count(old_content, count):
    pattern = re.compile(r"(?<!\d)" + str(count) + r"(?!\d)")
    deadline = time.time() + 3
    while time.time() < deadline:
        current = read_log()
        appended = current[len(old_content):] if current.startswith(old_content) else current
        if appended.strip() and pattern.search(appended):
            return
        time.sleep(0.05)
    pytest.fail(f"Server log did not record the processed record count {count} for the request")


def parse_json_lines(response):
    lines = response.text.strip().split('\n')
    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON on line {i+1}: {line}")
    return lines, records


def expected_records(input_rows):
    first_by_timestamp = {}
    for row in input_rows:
        if row[0] not in first_by_timestamp:
            first_by_timestamp[row[0]] = row

    minimum = min(first_by_timestamp)
    maximum = max(first_by_timestamp)
    output = []
    last_value = None
    for timestamp in range(minimum, maximum + 1):
        if timestamp in first_by_timestamp:
            _, value, user, text = first_by_timestamp[timestamp]
            if value is not None:
                last_value = value
            value = last_value
        else:
            value = last_value
            user = "SYSTEM"
            text = ""
        output.append({
            "timestamp": timestamp,
            "text_note": unicodedata.normalize("NFC", text).lower(),
            "sensor_val": value,
            "user_id": hashlib.sha256(user.encode('utf-8')).hexdigest(),
        })
    return output


def test_server_processing():
    """Test the HTTP server's processing logic."""
    payload = b""
    payload += pack_record(100, 5.5, "alice", "Mo\u0308tley")
    payload += pack_record(100, 5.5, "alice", "Mo\u0308tley")
    payload += pack_record(102, None, "bob", "CAF\u00c9")

    call_offset = os.path.getsize(CALL_LOG)
    try:
        response = requests.post(URL, headers=GOOD_HEADERS, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    wait_for_decoder_call(payload, call_offset)

    lines = response.text.strip().split('\n')
    assert len(lines) == 3, f"Expected 3 lines of JSON, got {len(lines)}"

    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON on line {i+1}: {line}")

    assert records[0]["timestamp"] == 100
    assert records[0]["text_note"] == "mötley"
    assert records[0]["sensor_val"] == 5.5
    assert records[0]["user_id"] == hashlib.sha256(b"alice").hexdigest()

    assert records[1]["timestamp"] == 101
    assert records[1]["text_note"] == ""
    assert records[1]["sensor_val"] == 5.5
    assert records[1]["user_id"] == hashlib.sha256(b"SYSTEM").hexdigest()

    assert records[2]["timestamp"] == 102
    assert records[2]["text_note"] == "café"
    assert records[2]["sensor_val"] == 5.5
    assert records[2]["user_id"] == hashlib.sha256(b"bob").hexdigest()


def test_randomized_processing_and_logging():
    rng = random.SystemRandom()
    notes = ["A\u030Angstro\u0308M", "CAFE\u0301", "MÜNCHEN", "E\u0301COLE", "ΜΉΝΥΜΑ"]

    for trial in range(4):
        base = rng.randrange(10000, 2000000000)
        middle = rng.randrange(2, 5)
        span = rng.randrange(middle + 2, middle + 7)
        initial_value = rng.choice([1.25, 2.5, 7.75, 11.5, 23.25])
        final_value = rng.choice([31.25, 42.5, 63.75, 88.0])
        first_user = f"u{rng.randrange(100000, 999999)}"
        middle_user = f"m{rng.randrange(100000, 999999)}"
        final_user = f"z{rng.randrange(100000, 999999)}"
        first_note = rng.choice(notes)
        middle_note = rng.choice(notes)
        final_note = rng.choice(notes)

        rows = [
            (base + span, final_value, final_user, final_note),
            (base, initial_value, first_user, first_note),
            (base, 999.0, "discarded", "WRONG"),
            (base + middle, None, middle_user, middle_note),
        ]
        payload = b''.join(pack_record(*row) for row in rows)
        expected = expected_records(rows)
        old_log = read_log()
        call_offset = os.path.getsize(CALL_LOG)

        response = requests.post(URL, headers=GOOD_HEADERS, data=payload, timeout=5)
        assert response.status_code == 200, response.text
        wait_for_decoder_call(payload, call_offset)
        lines, actual = parse_json_lines(response)
        assert len(lines) == span + 1
        assert actual == expected
        wait_for_logged_count(old_log, span + 1)


def test_server_unauthorized():
    """Test the HTTP server rejects unauthorized requests."""
    headers = {"Authorization": "Bearer wrong_token"}
    payload = pack_record(100, 5.5, "alice", "test")

    try:
        response = requests.post(URL, headers=headers, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code in [401, 403], f"Expected HTTP 401 or 403 for unauthorized request, got {response.status_code}"


def test_server_log_exists():
    """Test that the server log exists and has content."""
    assert os.path.exists(SERVER_LOG), f"Log file {SERVER_LOG} does not exist."
    with open(SERVER_LOG, 'r') as f:
        content = f.read()
    assert len(content.strip()) > 0, f"Log file {SERVER_LOG} is empty."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
