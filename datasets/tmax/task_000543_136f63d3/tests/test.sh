#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path
import pytest

INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def get_sanitizer_cmd():
    sh_path = Path("/home/user/sanitizer.sh")
    py_path = Path("/home/user/sanitizer.py")

    if sh_path.exists():
        if os.access(sh_path, os.X_OK):
            return [str(sh_path)]
        return ["bash", str(sh_path)]
    elif py_path.exists():
        if os.access(py_path, os.X_OK):
            return [str(py_path)]
        return ["python3", str(py_path)]
    return None


def run_sanitizer(cmd, input_data: bytes) -> bytes:
    result = subprocess.run(
        cmd,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    return result.stdout


def test_sanitizer_exists():
    cmd = get_sanitizer_cmd()
    assert cmd is not None, "Sanitizer script not found at /home/user/sanitizer.sh or /home/user/sanitizer.py"


def test_clean_corpus():
    cmd = get_sanitizer_cmd()
    assert cmd is not None, "Sanitizer script not found."

    clean_dir = Path("/app/corpora/clean")
    assert clean_dir.exists() and clean_dir.is_dir(), "Clean corpus directory missing."

    failed_files = []
    total_files = 0

    for csv_file in clean_dir.glob("*.csv"):
        total_files += 1
        input_data = csv_file.read_bytes()
        output_data = run_sanitizer(cmd, input_data)

        input_lines = [line for line in input_data.decode('utf-8', errors='replace').splitlines() if line.strip()]
        output_lines = [line for line in output_data.decode('utf-8', errors='replace').splitlines() if line.strip()]

        if input_lines != output_lines:
            failed_files.append(csv_file.name)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total_files} clean files modified: {', '.join(failed_files)}")


def test_evil_corpus():
    cmd = get_sanitizer_cmd()
    assert cmd is not None, "Sanitizer script not found."

    evil_dir = Path("/app/corpora/evil")
    assert evil_dir.exists() and evil_dir.is_dir(), "Evil corpus directory missing."

    failed_files = []
    total_files = 0

    for csv_file in evil_dir.glob("*.csv"):
        total_files += 1
        input_data = csv_file.read_bytes()
        output_data = run_sanitizer(cmd, input_data)

        output_lines = [line for line in output_data.decode('utf-8', errors='replace').splitlines() if line.strip()]

        if len(output_lines) > 0:
            failed_files.append(csv_file.name)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total_files} evil files bypassed: {', '.join(failed_files)}")


def test_derived_int32_boundaries_and_mixed_records():
    cmd = get_sanitizer_cmd()
    assert cmd is not None, "Sanitizer script not found."

    rng = random.Random(secrets.randbits(128))
    cases = [
        (0, 0),
        (INT32_MAX - 1000, 1),
        (INT32_MAX - 999, 1),
        (INT32_MIN - 1000, 1),
        (INT32_MIN - 1001, 1),
        (46340, 46340),
        (46341, 46341),
        (-46340, 46340),
        (-46341, 46341),
        (50000, 45000),
        (10, 10),
    ]

    for _ in range(500):
        amount = rng.randint(-2_000_000, 2_000_000)
        multiplier = rng.randint(-2_000_000, 2_000_000)
        cases.append((amount, multiplier))

    rng.shuffle(cases)
    base_id = rng.randrange(100_000_000, 900_000_000)
    input_lines = []
    expected_lines = []

    for index, (amount, multiplier) in enumerate(cases):
        transaction_id = base_id + index
        user_id = rng.randint(1, 1_000_000)
        line = f"{transaction_id},{user_id},{amount},{multiplier}\n".encode("ascii")
        input_lines.append(line)

        impact = amount * multiplier + 1000
        if INT32_MIN <= impact <= INT32_MAX:
            expected_lines.append(line)

    assert expected_lines, "Generated test unexpectedly contains no safe records"
    assert len(expected_lines) < len(input_lines), "Generated test unexpectedly contains no overflow records"

    result = subprocess.run(
        cmd,
        input=b"".join(input_lines),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"Sanitizer exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    assert result.stdout == b"".join(expected_lines), "Sanitizer did not exactly preserve safe records and drop all int32-overflow records"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
