#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import subprocess
from pathlib import Path

REPO = Path("/home/user/suspicious_repo")
REPORT = Path("/home/user/report.txt")
ACTIVE_MULTIPLIER = 0x11223344


def test_secret_params_recovered():
    secret_file = REPO / "secret_params.h"
    assert secret_file.is_file(), f"{secret_file} was not recovered."
    content = secret_file.read_text()
    assert "0x8a9b2c3d" in content.lower() or "2325433405" in content, \
        "The recovered secret_params.h does not contain the correct SECRET_MULTIPLIER."


def test_auth_math_was_not_modified():
    committed = subprocess.run(
        ["git", "show", "HEAD:auth_math.cpp"], cwd=REPO,
        check=True, stdout=subprocess.PIPE, text=True
    ).stdout
    assert (REPO / "auth_math.cpp").read_text() == committed, \
        "auth_math.cpp must not be modified; debug the instructed function as it exists at HEAD."


def test_report_exists_and_valid():
    assert REPORT.is_file(), f"Report file {REPORT} does not exist."

    lines = [line.strip() for line in REPORT.read_text().strip().split("\n") if line.strip()]
    assert len(lines) == 3, f"Report file must contain exactly 3 lines, found {len(lines)}."

    multiplier_str = lines[0].lower()
    assert "0x8a9b2c3d" in multiplier_str or "2325433405" in multiplier_str, \
        f"Line 1 of report is incorrect. Expected SECRET_MULTIPLIER, got: {lines[0]}"

    try:
        timestamp = int(lines[1])
    except ValueError:
        assert False, f"Line 2 must be a decimal integer, got: {lines[1]}"
    assert 0 <= timestamp <= 0xffffffff, "Line 2 must be a uint32_t timestamp."

    modulo_result = (timestamp * ACTIVE_MULTIPLIER) % 99991
    assert modulo_result == 1337, \
        f"The timestamp {timestamp} does not crash the calculate_token implementation at HEAD."

    hash_str = lines[2].lower()
    assert hash_str.startswith("0x"), \
        f"Line 3 must be a hexadecimal value prefixed with '0x', got: {lines[2]}"
    try:
        internal_hash = int(hash_str, 16)
    except ValueError:
        assert False, f"Line 3 must be a valid hexadecimal integer, got: {lines[2]}"

    expected_hash = timestamp * ACTIVE_MULTIPLIER
    assert internal_hash == expected_hash, \
        f"Line 3 internal_hash is incorrect. Expected hex({expected_hash}), got {hash_str}."


def test_fuzzer_created():
    fuzzer_file = REPO / "fuzzer.cpp"
    assert fuzzer_file.is_file(), f"Fuzzer source file {fuzzer_file} was not created."


def test_fuzzer_compiles_and_exercises_calculate_token():
    fuzzer_file = REPO / "fuzzer.cpp"
    source = fuzzer_file.read_text()
    assert re.search(r"LLVMFuzzerTestOneInput", source), \
        "fuzzer.cpp does not define a libFuzzer entry point."
    assert re.search(r"calculate_token\s*\(", source), \
        "fuzzer.cpp does not call calculate_token."

    binary = Path("/tmp/submission_fuzzer")
    build = subprocess.run(
        ["clang++", "-std=c++17", "-fsanitize=fuzzer,address", "-g",
         str(fuzzer_file), str(REPO / "auth_math.cpp"), "-o", str(binary)],
        cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=60
    )
    assert build.returncode == 0, f"fuzzer.cpp failed to compile as a libFuzzer harness:\n{build.stderr}"

    lines = [line.strip() for line in REPORT.read_text().strip().split("\n") if line.strip()]
    timestamp = int(lines[1])
    run_dir = Path("/tmp/fuzzer_verification")
    run_dir.mkdir(exist_ok=True)
    benign = run_dir / "benign.bin"
    crashing = run_dir / "crashing.bin"
    benign.write_bytes(struct.pack("=I", 0))
    crashing.write_bytes(struct.pack("=I", timestamp))

    benign_run = subprocess.run(
        [str(binary), "-runs=1", "-timeout=5", str(benign)],
        cwd=run_dir, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=20
    )
    assert benign_run.returncode == 0, \
        f"The fuzzer harness crashes on a benign four-byte timestamp:\n{benign_run.stderr}"

    crash_run = subprocess.run(
        [str(binary), "-runs=1", "-timeout=5", str(crashing)],
        cwd=run_dir, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=20
    )
    diagnostics = crash_run.stdout + crash_run.stderr
    assert crash_run.returncode != 0, \
        "The compiled fuzzer did not expose the memory violation for the reported timestamp."
    assert "AddressSanitizer" in diagnostics and re.search(
        r"DEADLYSIGNAL|SEGV|null", diagnostics, re.IGNORECASE
    ), f"The failing fuzzer run did not report the expected AddressSanitizer memory violation:\n{diagnostics}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
