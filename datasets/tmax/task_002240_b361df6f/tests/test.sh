#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_recovery.py
import os
import stat
import struct
import subprocess
import tempfile

BASE = "/home/user/db_recovery"
SOURCE = os.path.join(BASE, "recover.cpp")
BINARY = os.path.join(BASE, "recover")
WAL = os.path.join(BASE, "system_state.wal")
RECOVERED = os.path.join(BASE, "recovered_metrics.txt")

EXPECTED_LINES = [
    "active_connections=1042",
    "request_rate=500",
    "cpu_load_avg=3.14",
    "memory_usage_bytes=" + "9" * 1000,
    "uptime_seconds=86400",
]


def parse_wal(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"WAL1", "Invalid WAL magic in test input"
    pos = 4
    records = []
    while pos < len(data):
        assert pos + 2 <= len(data), "Truncated key length"
        key_len = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        assert pos + key_len <= len(data), "Truncated key"
        key = data[pos:pos + key_len]
        pos += key_len
        assert pos + 4 <= len(data), "Truncated value length"
        val_len = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        assert pos + val_len <= len(data), "Truncated value"
        value = data[pos:pos + val_len]
        pos += val_len
        records.append(key + b"=" + value)
    return b"\n".join(records) + (b"\n" if records else b"")


def run_tool(binary, wal):
    result = subprocess.run(
        [binary, wal], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        "Recovery tool failed with status %d: %s" %
        (result.returncode, result.stderr.decode("utf-8", "replace"))
    )
    return result.stdout


# Preserve the original file and fixed-content assertions.
assert os.path.isfile(RECOVERED), (
    "The file /home/user/db_recovery/recovered_metrics.txt is missing. "
    "Did you redirect the output?"
)
with open(RECOVERED, "r") as f:
    lines = f.read().strip().split("\n")
assert len(lines) == len(EXPECTED_LINES), (
    "Expected %d lines in recovered_metrics.txt, but got %d." %
    (len(EXPECTED_LINES), len(lines))
)
for i, (expected, actual) in enumerate(zip(EXPECTED_LINES, lines)):
    assert expected == actual, (
        "Mismatch on line %d. Expected '%s...', but got '%s...'." %
        (i + 1, expected[:50], actual[:50])
    )

assert os.path.isfile(SOURCE), "recover.cpp is missing."
with open(SOURCE, "r") as f:
    content = f.read()
assert "std::string key(key_buf);" not in content, (
    "recover.cpp still contains the buggy key string constructor."
)
assert "std::string val(val_buf);" not in content, (
    "recover.cpp still contains the buggy val string constructor."
)

# The requested artifact must exist, be executable, and be a native ELF binary.
assert os.path.isfile(BINARY), "The compiled recover executable is missing."
assert os.access(BINARY, os.X_OK), "The recover artifact is not executable."
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", "recover is not a compiled ELF executable."

# Execute the submitted artifact against the production WAL and ensure the
# redirected file is exactly its recovered record stream.
expected_original = parse_wal(WAL)
submitted_output = run_tool(BINARY, WAL)
assert submitted_output == expected_original, (
    "The compiled recover tool did not correctly parse system_state.wal."
)
with open(RECOVERED, "rb") as f:
    recovered_bytes = f.read()
assert recovered_bytes.rstrip(b"\n") == submitted_output.rstrip(b"\n"), (
    "recovered_metrics.txt does not match the fixed program's output."
)

# Compile the submitted source independently so a stale or hardcoded artifact
# cannot substitute for a real source fix.
verified_binary = "/tmp/recover_verified"
compile_result = subprocess.run(
    ["g++", "-O0", "-g", "-std=c++11", SOURCE, "-o", verified_binary],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
)
assert compile_result.returncode == 0, (
    "recover.cpp does not compile: " +
    compile_result.stderr.decode("utf-8", "replace")
)
assert run_tool(verified_binary, WAL) == expected_original, (
    "The submitted source does not correctly parse system_state.wal."
)

# Exercise the rebuilt source on a fresh WAL whose records are generated only
# at verification time, preventing a fixed-output implementation from passing.
nonce = os.urandom(16).hex().encode("ascii")
records = [
    (b"short_" + nonce[:8], b"7"),
    (b"metric_" + nonce[8:20], b"value_" + nonce),
    (b"long_value_" + nonce[20:], b"A" * 4097),
    (b"tail_" + nonce[:12], b"done_" + nonce[::-1]),
]
fd, challenge_wal = tempfile.mkstemp(prefix="recovery_challenge_", suffix=".wal")
os.close(fd)
try:
    with open(challenge_wal, "wb") as f:
        f.write(b"WAL1")
        for key, value in records:
            f.write(struct.pack("<H", len(key)))
            f.write(key)
            f.write(struct.pack("<I", len(value)))
            f.write(value)
    challenge_expected = parse_wal(challenge_wal)
    assert run_tool(verified_binary, challenge_wal) == challenge_expected, (
        "The recovery implementation failed on a valid verification-time WAL."
    )
finally:
    os.unlink(challenge_wal)
PY_EOF

if python3 /tmp/verify_recovery.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
