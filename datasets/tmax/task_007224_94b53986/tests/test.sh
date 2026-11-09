#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/wal_compiler.c"
EXECUTABLE_PATH = "/home/user/wal_compiler"
OUTPUT_PATH = "/home/user/compiled_config.txt"
WAL_DIR = "/home/user/wals"


def test_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(SOURCE_PATH), "The source file /home/user/wal_compiler.c is missing."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE_PATH), f"The executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"The file {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF binary."


def run_compiler(binary):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{binary} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"{binary} did not create {OUTPUT_PATH}."
    with open(OUTPUT_PATH, "r", encoding="ascii") as f:
        return f.read()


def test_compiled_config_output():
    """Run the submitted executable and test the provided WAL files."""
    actual_output = run_compiler(EXECUTABLE_PATH)

    expected_output = (
        "debug=false\n"
        "hostname=server02\n"
        "port=8081\n"
        "retry_count=5\n"
    )

    assert actual_output.strip() == expected_output.strip(), (
        f"The content of {OUTPUT_PATH} is incorrect.\n"
        f"Expected:\n{expected_output.strip()}\n"
        f"Actual:\n{actual_output.strip()}"
    )

    lines = [line for line in actual_output.strip().split("\n") if line]
    assert sorted(lines) == lines, "The output lines are not sorted alphabetically by key."


def write_wal(path, records):
    with open(path, "wb") as f:
        f.write(b"CFGWAL01")
        for timestamp, key, value in records:
            key_bytes = key.encode("ascii")
            value_bytes = value.encode("ascii")
            f.write(struct.pack("<IBH", timestamp, len(key_bytes), len(value_bytes)))
            f.write(key_bytes)
            f.write(value_bytes)


def expected_output(files):
    state = {}
    for records in files:
        for timestamp, key, value in records:
            previous = state.get(key)
            if previous is None or timestamp > previous[0]:
                state[key] = (timestamp, value)
    lines = [f"{key}={value}" for key, (_, value) in state.items() if value != ""]
    lines.sort()
    return "\n".join(lines)


def install_dynamic_wals():
    shutil.rmtree(WAL_DIR, ignore_errors=True)
    os.makedirs(WAL_DIR)

    token = secrets.token_hex(8)
    base = 100000 + secrets.randbelow(100000000)
    alpha = "alpha_" + token
    deleted = "deleted_" + token
    long_key = "long_" + token
    revived = "revived_" + token
    zeta = "zeta_" + token

    files = [
        [
            (base + 100, zeta, "old_" + token),
            (base + 500, alpha, "current_" + token),
            (base + 300, deleted, "present_" + token),
            (base + 700, long_key, ("L" + token) * 20),
        ],
        [
            (base + 900, zeta, "new_" + token),
            (base + 800, deleted, ""),
            (base + 200, alpha, "stale_" + token),
            (base + 600, revived, ""),
        ],
        [
            (base + 1000, revived, "live_" + token),
            (base + 50, zeta, "very_stale_" + token),
        ],
        [],
    ]

    write_wal(os.path.join(WAL_DIR, "first_" + token + ".wal"), files[0])
    write_wal(os.path.join(WAL_DIR, "second_" + token + ".wal"), files[1])
    write_wal(os.path.join(WAL_DIR, "third_" + token + ".wal"), files[2])
    write_wal(os.path.join(WAL_DIR, "empty_" + token + ".wal"), files[3])

    # A correctly formatted WAL with the wrong extension must not be parsed.
    write_wal(
        os.path.join(WAL_DIR, "ignore_" + token + ".txt"),
        [(base + 5000, "intruder_" + token, "must_not_appear")],
    )
    return expected_output(files)


def assert_dynamic_behavior(binary):
    expected = install_dynamic_wals()
    actual = run_compiler(binary)
    assert actual.strip() == expected.strip(), (
        f"{binary} produced the wrong result for dynamically generated WAL files.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )
    lines = [line for line in actual.strip().split("\n") if line]
    assert lines == sorted(lines), "The output lines are not sorted alphabetically by key."
    assert all("=" in line for line in lines), "Output contains a malformed configuration line."


def test_submitted_executable_on_dynamic_wals():
    """Exercise the submitted executable on unpredictable WAL contents."""
    assert_dynamic_behavior(EXECUTABLE_PATH)


def test_source_builds_and_implements_parser():
    """Build the submitted source independently and exercise that binary too."""
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "wal_compiler")
        result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            "The submitted C source does not compile with gcc.\n"
            + result.stderr.decode(errors="replace")
        )
        assert_dynamic_behavior(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
