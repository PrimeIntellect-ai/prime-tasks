#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

HASHER=/app/legacy_hasher
REAL_HASHER=/app/legacy_hasher.verifier-real
CALL_LOG=/tmp/legacy_hasher_calls.log

cleanup() {
    if [ -e "$REAL_HASHER" ]; then
        rm -f "$HASHER"
        mv "$REAL_HASHER" "$HASHER"
        chmod +x "$HASHER"
    fi
}
trap cleanup EXIT

rm -f "$REAL_HASHER" "$CALL_LOG"
if ! mv "$HASHER" "$REAL_HASHER"; then
    exit 0
fi

cat > "$HASHER" <<'WRAPPER_EOF'
#!/bin/sh
printf '%s\n' "$1" >> /tmp/legacy_hasher_calls.log
exec /app/legacy_hasher.verifier-real "$@"
WRAPPER_EOF
chmod +x "$HASHER"
touch "$CALL_LOG"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import http.client
import json
import os
import random
import secrets
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:9090/api/v1/process"
LOG_PATH = "/home/user/etl_metrics.log"
CALL_LOG = "/tmp/legacy_hasher_calls.log"
REAL_HASHER = "/app/legacy_hasher.verifier-real"


def get_legacy_hash(user_id):
    try:
        return subprocess.check_output([REAL_HASHER, user_id], text=True, timeout=5).strip()
    except Exception as exc:
        pytest.fail(f"Failed to execute legacy_hasher for {user_id}: {exc}")


def make_mixed_records(count):
    retained = []
    dropped = []
    for index in range(500):
        user_id = "u" + secrets.token_hex(12)
        token = get_legacy_hash(user_id)
        record = {
            "user_id": user_id,
            "email": f"person-{secrets.token_hex(5)}@example.test",
            "event": ["click", "view", "purchase", "login"][index % 4],
            "sequence": index,
            "metadata": {"nonce": secrets.token_hex(6), "active": index % 2 == 0},
        }
        (retained if token and token[0].lower() in "abcdef" else dropped).append(record)
        if len(retained) >= (count + 1) // 2 and len(dropped) >= count // 2:
            result = retained[: (count + 1) // 2] + dropped[: count // 2]
            random.SystemRandom().shuffle(result)
            return result
    pytest.fail("Could not generate records from both hash strata")


def expected_records(records):
    result = []
    for record in records:
        token = get_legacy_hash(record["user_id"])
        if token and token[0].lower() in "abcdef":
            expected = record.copy()
            expected["email"] = "***@***.***"
            expected["secure_token"] = token
            result.append(expected)
    return result


def parse_and_check_response(status, body, expected):
    assert status == 200, f"Expected HTTP 200 OK, got {status}. Response: {body}"
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    actual = []
    for line in lines:
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Server returned invalid JSONL: {line}")
        assert isinstance(value, dict), f"Each output JSONL value must be an object: {line}"
        actual.append(value)

    assert len(actual) == len(expected), (
        f"Expected {len(expected)} retained records, but got {len(actual)}"
    )
    for wanted, received in zip(expected, actual):
        assert received == wanted, f"Mismatch in record. Expected: {wanted!r}; actual: {received!r}"


def read_metrics():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created"
    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        return handle.read().splitlines()


def check_one_metric_line(before, processed, retained):
    wanted = f"PROCESSED:{processed}|RETAINED:{retained}"
    deadline = time.time() + 3
    after = read_metrics()
    while time.time() < deadline and len(after) < len(before) + 1:
        time.sleep(0.05)
        after = read_metrics()

    assert after == before + [wanted], (
        "Each completed request must append exactly one metrics line with exact counts. "
        f"Expected appended line {wanted!r}; before={before!r}, after={after!r}"
    )

    last_line = after[-1]
    assert last_line.startswith("PROCESSED:")
    assert "|RETAINED:" in last_line
    parts = last_line.split("|")
    assert len(parts) == 2
    processed_part = parts[0].split(":")
    retained_part = parts[1].split(":")
    assert len(processed_part) == 2 and processed_part[1].isdigit()
    assert len(retained_part) == 2 and retained_part[1].isdigit()


def reset_calls():
    with open(CALL_LOG, "w", encoding="utf-8"):
        pass


def read_calls():
    with open(CALL_LOG, "r", encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def check_hasher_calls(records):
    wanted = collections.Counter(record["user_id"] for record in records)
    deadline = time.time() + 3
    calls = read_calls()
    while time.time() < deadline and len(calls) < len(records):
        time.sleep(0.05)
        calls = read_calls()
    assert collections.Counter(calls) == wanted, (
        "The server must invoke /app/legacy_hasher for every input user_id. "
        f"Expected {wanted}, got {collections.Counter(calls)}"
    )


def ordinary_request(records, trailing_newline):
    expected = expected_records(records)
    payload = "\n".join(json.dumps(record, separators=(",", ":")) for record in records)
    if trailing_newline:
        payload += "\n"

    before = read_metrics()
    reset_calls()
    try:
        response = requests.post(
            URL,
            data=payload.encode("utf-8"),
            headers={"Content-Type": "application/x-ndjson"},
            timeout=10,
        )
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the ETL server at {URL}: {exc}")

    parse_and_check_response(response.status_code, response.text, expected)
    check_hasher_calls(records)
    check_one_metric_line(before, len(records), len(expected))


def streaming_request(records):
    expected = expected_records(records)
    encoded_lines = [json.dumps(r, separators=(",", ":")).encode("utf-8") for r in records]
    prefix = encoded_lines[0] + b"\n"
    suffix = b"\n".join(encoded_lines[1:])
    full_length = len(prefix) + len(suffix)

    before = read_metrics()
    reset_calls()
    connection = http.client.HTTPConnection("127.0.0.1", 9090, timeout=10)
    try:
        connection.putrequest("POST", "/api/v1/process")
        connection.putheader("Content-Type", "application/x-ndjson")
        connection.putheader("Content-Length", str(full_length))
        connection.putheader("Connection", "close")
        connection.endheaders()

        # Send one complete JSONL row while deliberately withholding the rest of
        # the declared body. A streaming implementation must begin processing it.
        connection.send(prefix)
        first_id = records[0]["user_id"]
        deadline = time.time() + 4
        while time.time() < deadline and first_id not in read_calls():
            time.sleep(0.05)
        assert first_id in read_calls(), (
            "The server did not process a complete JSONL row until the full HTTP "
            "payload was available; incoming data must be processed as a stream"
        )

        connection.send(suffix)
        response = connection.getresponse()
        body = response.read().decode("utf-8")
        status = response.status
    finally:
        connection.close()

    parse_and_check_response(status, body, expected)
    check_hasher_calls(records)
    check_one_metric_line(before, len(records), len(expected))


def test_etl_stream_processing_and_metrics():
    ordinary_request(make_mixed_records(7), trailing_newline=False)
    ordinary_request(make_mixed_records(19), trailing_newline=True)
    streaming_request(make_mixed_records(10))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
