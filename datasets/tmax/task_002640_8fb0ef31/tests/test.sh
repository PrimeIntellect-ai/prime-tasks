#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

ORIGINAL=/tmp/verifier_legacy_bytecode_gen
INVOCATIONS=/tmp/verifier_legacy_invocations.log
CHALLENGES=/tmp/verifier_challenge_ids
BYTECODES=/tmp/verifier_generated_bytecodes.jsonl

mv /app/legacy_bytecode_gen "$ORIGINAL"
: > "$INVOCATIONS"
: > "$BYTECODES"
chmod 666 "$INVOCATIONS" "$BYTECODES"

python3 - <<'PY' > "$CHALLENGES"
import secrets
ids = set()
while len(ids) < 6:
    value = secrets.randbelow(2_000_000_001) - 1_000_000_000
    if value not in (42, 99):
        ids.add(value)
for value in ids:
    print(value)
PY
chmod 644 "$CHALLENGES"

cat <<'WRAPPER_EOF' > /app/legacy_bytecode_gen
#!/usr/bin/env python3
import json
import os
import secrets
import struct
import sys

ORIGINAL = "/tmp/verifier_legacy_bytecode_gen"
INVOCATIONS = "/tmp/verifier_legacy_invocations.log"
CHALLENGES = "/tmp/verifier_challenge_ids"
BYTECODES = "/tmp/verifier_generated_bytecodes.jsonl"

artifact_id = int(sys.argv[1])
with open(INVOCATIONS, "a") as f:
    f.write(str(artifact_id) + "\n")

with open(CHALLENGES) as f:
    challenge_ids = {int(line) for line in f if line.strip()}

if artifact_id not in challenge_ids:
    os.execv(ORIGINAL, [ORIGINAL] + sys.argv[1:])

instructions = [
    (0x01, secrets.randbelow(256), 0),
    (0x01, secrets.randbelow(256), 1),
    (0x04, secrets.randbelow(256), 0),
    (0x02, 0, 1),
    (0x03, 0, 1),
    (0x04, secrets.randbelow(256), 1),
]
for _ in range(16):
    op = secrets.choice((0x01, 0x02, 0x03, 0x04))
    if op in (0x01, 0x04):
        instructions.append((op, secrets.randbelow(256), secrets.randbelow(2)))
    else:
        instructions.append((op, secrets.randbelow(2), secrets.randbelow(2)))
instructions.append((0xFF, secrets.randbelow(256), secrets.randbelow(256)))
data = b"".join(struct.pack("BBB", *instruction) for instruction in instructions)
with open("output.bin", "wb") as f:
    f.write(data)
with open(BYTECODES, "a") as f:
    f.write(json.dumps({"artifact_id": artifact_id, "bytecode": data.hex()}) + "\n")
WRAPPER_EOF
chmod 755 /app/legacy_bytecode_gen

cleanup() {
    rm -f /app/legacy_bytecode_gen
    if [ -e "$ORIGINAL" ]; then
        mv "$ORIGINAL" /app/legacy_bytecode_gen
    fi
}
trap cleanup EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import struct
import subprocess
import tempfile

import pytest
import requests

URL = "http://127.0.0.1:9090/process_artifact"
HEADERS = {"X-CI-Token": "build-eng-2024"}
ORIGINAL = "/tmp/verifier_legacy_bytecode_gen"
INVOCATIONS = "/tmp/verifier_legacy_invocations.log"
CHALLENGES = "/tmp/verifier_challenge_ids"
BYTECODES = "/tmp/verifier_generated_bytecodes.jsonl"


def emulate_bytes(data):
    reg = [0, 0]
    for offset in range(0, len(data) - 2, 3):
        op, arg1, arg2 = struct.unpack("BBB", data[offset:offset + 3])
        if op == 0x01:
            reg[arg2] = arg1
        elif op == 0x02:
            reg[arg2] = (reg[arg2] + reg[arg1]) % 256
        elif op == 0x03:
            reg[arg2] = (reg[arg2] * reg[arg1]) % 256
        elif op == 0x04:
            reg[arg2] = reg[arg2] ^ arg1
        elif op == 0xFF:
            break
    return reg[1]


def emulate_bytecode(filename):
    with open(filename, "rb") as f:
        return emulate_bytes(f.read())


def get_expected_checksum(artifact_id):
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run([ORIGINAL, str(artifact_id)], cwd=directory, check=True)
        return emulate_bytecode(os.path.join(directory, "output.bin"))


def invocation_count(artifact_id):
    with open(INVOCATIONS) as f:
        return sum(line.strip() == str(artifact_id) for line in f)


def generated_bytecode(artifact_id):
    matches = []
    with open(BYTECODES) as f:
        for line in f:
            if line.strip():
                record = json.loads(line)
                if record["artifact_id"] == artifact_id:
                    matches.append(bytes.fromhex(record["bytecode"]))
    assert matches, f"Legacy generator was not invoked for artifact {artifact_id}"
    return matches[-1]


def assert_valid_response(resp, expected):
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    data = resp.json()
    assert "checksum" in data, f"Response JSON missing 'checksum' key. Response: {data}"
    assert data["checksum"] == expected, f"Expected checksum {expected}, got {data['checksum']}"


def test_unauthorized_missing_header():
    resp = requests.post(URL, json={"artifact_id": 1})
    assert resp.status_code == 401, f"Expected 401 for missing header, got {resp.status_code}. Response: {resp.text}"


def test_unauthorized_wrong_header():
    headers = {"X-CI-Token": "wrong-token"}
    resp = requests.post(URL, headers=headers, json={"artifact_id": 1})
    assert resp.status_code == 401, f"Expected 401 for wrong header, got {resp.status_code}. Response: {resp.text}"


def test_valid_request_42():
    expected = get_expected_checksum(42)
    before = invocation_count(42)
    resp = requests.post(URL, headers=HEADERS, json={"artifact_id": 42})
    assert_valid_response(resp, expected)
    assert invocation_count(42) > before, "The service did not invoke /app/legacy_bytecode_gen for artifact 42"


def test_valid_request_99():
    expected = get_expected_checksum(99)
    before = invocation_count(99)
    resp = requests.post(URL, headers=HEADERS, json={"artifact_id": 99})
    assert_valid_response(resp, expected)
    assert invocation_count(99) > before, "The service did not invoke /app/legacy_bytecode_gen for artifact 99"


with open(CHALLENGES) as f:
    CHALLENGE_IDS = [int(line) for line in f if line.strip()]


@pytest.mark.parametrize("artifact_id", CHALLENGE_IDS)
def test_randomized_bytecode_and_artifact_id(artifact_id):
    before = invocation_count(artifact_id)
    resp = requests.post(URL, headers=HEADERS, json={"artifact_id": artifact_id})
    assert invocation_count(artifact_id) > before, f"The service did not invoke /app/legacy_bytecode_gen for artifact {artifact_id}"
    expected = emulate_bytes(generated_bytecode(artifact_id))
    assert_valid_response(resp, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
