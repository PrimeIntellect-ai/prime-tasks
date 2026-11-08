#!/bin/bash
set -e
mkdir -p /logs/verifier

verify() {
    test -f /home/user/analyzer.c || return 1
    test -f /home/user/exploit_gen.c || return 1

    gcc -std=c11 -O2 -Wall -Wextra /home/user/analyzer.c -o /tmp/analyzer_submission || return 1
    gcc -std=c11 -O2 -Wall -Wextra /home/user/exploit_gen.c -o /tmp/exploit_gen_submission || return 1

    # Recreate the canonical inputs, then require the submitted programs to
    # generate all three outputs themselves.
    python3 - <<'PY' || return 1
import struct

records = [
    (1690000000, 0x0A000001, b"AUTH_NORMAL_TOKEN_123"),
    (1690000005, 0x0A000002, b"A" * 55),
    (1690000010, 0x0A000003, b"\xde\xad\xbe\xef" + b"B" * 124),
    (1690000015, 0x0A000004, b"AUTH_SECRET_XYZ"),
]
with open("/home/user/traffic_log.bin", "wb") as f:
    for ts, ip, token in records:
        f.write(struct.pack("<IIH", ts, ip, len(token)))
        f.write(token)
with open("/home/user/auth_crashes.log", "w") as f:
    f.write("[INFO] Service started at 1690000000\n")
    f.write("[WARN] Invalid login attempt\n")
    f.write("[FATAL] Crash detected at timestamp 1690000010\n")
PY

    rm -f /home/user/processed_log.bin /home/user/crash_token.txt /home/user/exploit.bin
    (cd /home/user && timeout 10 /tmp/analyzer_submission) || return 1
    (cd /home/user && timeout 10 /tmp/exploit_gen_submission) || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import struct

def test_processed_log():
    path = "/home/user/processed_log.bin"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected_records = [
        (1690000000, 0x0A000001, b"\x00" * 21),
        (1690000005, 0x0A000002, b"A" * 55),
        (1690000010, 0x0A000003, b"\xde\xad\xbe\xef" + b"B" * 124),
        (1690000015, 0x0A000004, b"\x00" * 15)
    ]

    expected_content = b""
    for ts, ip, token in expected_records:
        expected_content += struct.pack("<I I H", ts, ip, len(token))
        expected_content += token

    with open(path, "rb") as f:
        content = f.read()

    assert content == expected_content, f"Content of {path} does not match expected processed state."

def test_crash_token():
    path = "/home/user/crash_token.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected_token = b"\xde\xad\xbe\xef" + b"B" * 124
    expected_hex = expected_token.hex().upper()

    with open(path, "r") as f:
        content = f.read()

    assert content == expected_hex, f"Content of {path} does not match expected crash token hex string."

def test_exploit_bin():
    path = "/home/user/exploit.bin"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected_token = b"\xde\xad\xbe\xef" + b"A" * 124
    expected_content = struct.pack("<I I H", 1700000000, 0x01020304, 128) + expected_token

    with open(path, "rb") as f:
        content = f.read()

    assert content == expected_content, f"Content of {path} does not match the expected exploit payload."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise analyzer.c on an unpredictable second capture so fixture bytes
    # cannot simply be hardcoded into the output files or program.
    python3 - <<'PY' || return 1
import secrets
import struct

base = 1800000000 + secrets.randbelow(100000000)
records = [
    (base,     secrets.randbits(32), secrets.token_bytes(7)),
    (base + 3, secrets.randbits(32), secrets.token_bytes(50)),
    (base + 8, secrets.randbits(32), secrets.token_bytes(51)),
    (base + 9, secrets.randbits(32), secrets.token_bytes(93)),
]
with open("/home/user/traffic_log.bin", "wb") as f:
    for ts, ip, token in records:
        f.write(struct.pack("<IIH", ts, ip, len(token)))
        f.write(token)
with open("/home/user/auth_crashes.log", "w") as f:
    f.write(f"[INFO] Service started at {base}\n")
    f.write("[WARN] Invalid login attempt\n")
    f.write(f"[FATAL] Crash detected at timestamp {base + 3}\n")
PY

    rm -f /home/user/processed_log.bin /home/user/crash_token.txt
    (cd /home/user && timeout 10 /tmp/analyzer_submission) || return 1

    python3 - <<'PY' || return 1
import os
import re
import struct

records = []
with open("/home/user/traffic_log.bin", "rb") as f:
    data = f.read()
offset = 0
while offset < len(data):
    assert len(data) - offset >= 10
    ts, ip, length = struct.unpack_from("<IIH", data, offset)
    offset += 10
    assert len(data) - offset >= length
    token = data[offset:offset + length]
    offset += length
    records.append((ts, ip, token))
assert offset == len(data)

with open("/home/user/auth_crashes.log", "r") as f:
    crash_log = f.read()
match = re.search(r"Crash detected at timestamp\s+(\d+)", crash_log)
assert match is not None
crash_timestamp = int(match.group(1))
crash_tokens = [token for ts, _ip, token in records if ts == crash_timestamp]
assert len(crash_tokens) == 1

expected_processed = bytearray()
for ts, ip, token in records:
    output_token = token if len(token) > 50 else b"\x00" * len(token)
    expected_processed += struct.pack("<IIH", ts, ip, len(token))
    expected_processed += output_token

assert os.path.isfile("/home/user/processed_log.bin")
with open("/home/user/processed_log.bin", "rb") as f:
    actual_processed = f.read()
assert actual_processed == bytes(expected_processed)

assert os.path.isfile("/home/user/crash_token.txt")
with open("/home/user/crash_token.txt", "rb") as f:
    actual_crash_token = f.read()
assert actual_crash_token == crash_tokens[0].hex().upper().encode("ascii")
PY
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
