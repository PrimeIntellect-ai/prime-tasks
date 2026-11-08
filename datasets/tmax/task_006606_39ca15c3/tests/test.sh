#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

WORKSPACE = Path("/home/user/incident-104")
BINARY = WORKSPACE / "data_processor"
SOURCE = WORKSPACE / "processor.c"
CORE = WORKSPACE / "core"
TOKEN_FILE = WORKSPACE / ".secret_token"
RESOLUTION = WORKSPACE / "resolution.txt"


def token_from_core():
    data = CORE.read_bytes()
    matches = re.findall(rb"TOKEN_[A-Za-z0-9]{10}", data)
    assert matches, "No 16-character TOKEN_ authentication token was found in the core dump"
    assert len(set(matches)) == 1, "The core dump contains multiple candidate authentication tokens"
    return matches[0].decode("ascii")


def test_resolution_file_content():
    assert RESOLUTION.exists(), f"File {RESOLUTION} does not exist. Did you save the final hash?"
    content = RESOLUTION.read_text().strip()
    expected_hash = "SUCCESS_HASH_12"
    assert expected_hash in content, f"Expected {RESOLUTION} to contain '{expected_hash}', but found: '{content}'"


def test_secret_token_file():
    assert TOKEN_FILE.exists(), f"File {TOKEN_FILE} does not exist. Did you find the missing initialization file path?"
    content = TOKEN_FILE.read_text().strip()
    expected_token = "TOKEN_8f9a2b4c6d"
    assert content.startswith(expected_token), f"Expected {TOKEN_FILE} to contain the token '{expected_token}'"
    assert content == token_from_core(), "The initialization file does not contain exactly the token present in the core dump"


def test_patch_was_applied_and_binary_rebuilt():
    assert SOURCE.is_file(), "processor.c is missing"
    source = SOURCE.read_text()
    assert "double res = sqrt(val);" in source, "The supplied mathematical patch was not applied to processor.c"
    assert "double res = val / 2.0;" not in source, "The old incorrect division remains in processor.c"

    assert BINARY.is_file(), "The rebuilt data_processor executable is missing"
    assert os.access(BINARY, os.X_OK), "data_processor is not executable"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "data_processor is not a compiled ELF executable"
    assert BINARY.stat().st_mtime_ns >= SOURCE.stat().st_mtime_ns, "data_processor predates the patched source and was not rebuilt"

    header = subprocess.run(["readelf", "-h", str(BINARY)], capture_output=True, text=True)
    assert header.returncode == 0 and "ELF Header" in header.stdout, "data_processor is not a valid ELF executable"

    dynamic = subprocess.run(["readelf", "-d", str(BINARY)], capture_output=True, text=True)
    symbols = subprocess.run(["nm", "-a", str(BINARY)], capture_output=True, text=True)
    linked_math = "libm.so" in dynamic.stdout or re.search(r"\b(?:sqrt|__ieee754_sqrt)\b", symbols.stdout)
    assert linked_math, "The rebuilt executable does not show evidence that the standard math library was linked"


def test_rebuilt_daemon_is_actually_executed_and_matches_resolution():
    expected_token = token_from_core()

    try:
        TOKEN_FILE.write_text("TOKEN_0000000000\n")
        rejected = subprocess.run(
            [str(BINARY)], cwd=WORKSPACE, capture_output=True, text=True, timeout=10
        )
        assert rejected.returncode != 0, "data_processor accepted an invalid authentication token"

        TOKEN_FILE.write_text(expected_token + "\n")
        completed = subprocess.run(
            [str(BINARY)], cwd=WORKSPACE, capture_output=True, text=True, timeout=10
        )
        assert completed.returncode == 0, (
            f"The rebuilt data_processor failed: stdout={completed.stdout!r}, stderr={completed.stderr!r}"
        )
        actual_output = completed.stdout.strip()
        assert actual_output == "SUCCESS_HASH_12", f"Unexpected daemon output: {actual_output!r}"
        assert RESOLUTION.read_text().strip() == actual_output, "resolution.txt is not exactly the hash output by the rebuilt daemon"
    finally:
        TOKEN_FILE.write_text(expected_token + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
