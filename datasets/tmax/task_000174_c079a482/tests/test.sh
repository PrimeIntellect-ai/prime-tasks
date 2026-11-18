#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
from decimal import Decimal

import pytest

REPO = "/home/user/perf_tools"
SCRIPT = os.path.join(REPO, "analyze_profile.sh")


def run_script(input_text, start_time):
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="profile_", suffix=".txt") as f:
        f.write(input_text)
        input_path = f.name

    try:
        result = subprocess.run(
            [SCRIPT, input_path, str(start_time)],
            cwd=REPO,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    finally:
        os.unlink(input_path)

    assert result.returncode == 0, (
        f"analyze_profile.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result.stdout.strip()


def expected_report(records, start_time):
    selected = [value for timestamp, value in records if timestamp >= start_time]
    assert selected
    average = sum(selected, Decimal("0")) / Decimal(len(selected))
    return f"Processed: {len(selected)} records\nAverage Latency: {average:.3f} ms"


def test_extracted_records_file():
    extracted_path = "/home/user/extracted_records.txt"
    assert os.path.isfile(extracted_path), f"Extracted records missing: {extracted_path}"

    with open(extracted_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1699999999 45.5",
        "1700000050 10.2",
        "1700000060 15.5",
        "1700000070 20.1",
        "1700000080 30.0",
    ]
    assert lines == expected_lines, f"Extracted records incorrect.\nExpected: {expected_lines}\nGot: {lines}"


def test_bad_commit_file():
    truth_path = "/tests/.truth_bad_commit"
    student_path = "/home/user/bad_commit.txt"

    assert os.path.isfile(truth_path), f"Verifier oracle missing: {truth_path}"
    assert os.path.isfile(student_path), f"Student file missing: {student_path}"

    with open(truth_path, "r") as f:
        truth_hash = f.read().strip()
    with open(student_path, "r") as f:
        student_hash = f.read().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", student_hash), "bad_commit.txt must contain one full 40-character commit hash"
    assert student_hash == truth_hash, f"Expected bad commit hash {truth_hash}, but got {student_hash}"


def test_repaired_script_exists_and_is_executable():
    assert os.path.isfile(SCRIPT), f"Required script missing: {SCRIPT}"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"Required script is not a regular file: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Required script is not executable: {SCRIPT}"

    branch = subprocess.run(
        ["git", "branch", "--show-current"], cwd=REPO, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True
    ).stdout.strip()
    assert branch == "master", f"Fix must be applied on master; current branch is {branch!r}"

    reference = subprocess.run(
        ["git", "show", "v1.0:analyze_profile.sh"], cwd=REPO,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True
    ).stdout
    with open(SCRIPT, "rb") as f:
        submitted = f.read()
    assert submitted != reference, "analyze_profile.sh must be repaired on master, not replaced byte-for-byte with the shipped v1.0 reference"


def test_script_on_required_input_and_final_report():
    expected_content = "Processed: 4 records\nAverage Latency: 18.950 ms"
    actual = run_script("1699999999 45.5\n1700000050 10.2\n1700000060 15.5\n1700000070 20.1\n1700000080 30.0\n", 1700000000)
    assert actual == expected_content, f"Repaired script output incorrect.\nExpected:\n{expected_content}\nGot:\n{actual}"

    report_path = "/home/user/final_report.txt"
    assert os.path.isfile(report_path), f"Final report missing: {report_path}"
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == expected_content, f"Final report content incorrect.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_script_handles_precision_boundary_and_raw_start_time():
    rng = secrets.SystemRandom()
    for _ in range(4):
        start = rng.randrange(1800000000, 1900000000)
        records = [
            (start - rng.randrange(1, 3599), Decimal(f"{rng.randrange(100, 900)}.{rng.randrange(1, 99):02d}")),
            (start - rng.randrange(3601, 9000), Decimal(f"{rng.randrange(100, 900)}.{rng.randrange(1, 99):02d}")),
            (start, Decimal(f"{rng.randrange(1, 80)}.{rng.randrange(1, 99):02d}")),
            (start + 17, Decimal(f"{rng.randrange(1, 80)}.{rng.randrange(1, 99):02d}")),
            (start + 41, Decimal(f"{rng.randrange(1, 80)}.{rng.randrange(1, 99):02d}")),
        ]
        input_text = "".join(f"{timestamp} {value}\n" for timestamp, value in records)
        expected = expected_report(records, start)
        actual = run_script(input_text, start)
        assert actual == expected, f"Script failed a generated regression case.\nExpected:\n{expected}\nGot:\n{actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
