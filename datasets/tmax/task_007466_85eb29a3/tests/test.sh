#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import uuid

import pytest

ROOT = "/home/user/ticket_system"
SCRIPT = os.path.join(ROOT, "calc_checksums.sh")
RESULTS_FILE = os.path.join(ROOT, "final_results.txt")


def test_final_results_file():
    assert os.path.isfile(RESULTS_FILE), f"The file {RESULTS_FILE} does not exist. Did you run the script and redirect the output?"

    with open(RESULTS_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_results = {
        "data/batch_1.txt: 6",
        "data/batch_2.txt: 6",
        "data/batch_3.txt: 14",
        "data/batch_4.txt: 6",
        "data/batch_5.txt: 6",
        "data/batch_6.txt: 6",
        "data/batch_7.txt: 21",
        "data/batch_8.txt: 6",
        "data/batch_9.txt: 6",
        "data/batch_10.txt: 6"
    }

    actual_results = set(lines)
    missing = expected_results - actual_results
    unexpected = actual_results - expected_results

    assert not missing, f"Missing expected results in {RESULTS_FILE}: {missing}"
    assert not unexpected, f"Unexpected results found in {RESULTS_FILE}: {unexpected}"
    assert len(lines) == 10, f"Expected exactly 10 lines in {RESULTS_FILE}, but found {len(lines)}"


def test_entrypoint_exists_and_reproduces_final_results():
    assert os.path.isfile(SCRIPT), f"Missing entrypoint: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Entrypoint is not executable: {SCRIPT}"

    proc = subprocess.run(
        ["bash", "-c", "./calc_checksums.sh data/batch_*.txt"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert proc.returncode == 0, f"calc_checksums.sh failed: {proc.stderr.decode(errors='replace')}"

    with open(RESULTS_FILE, "rb") as f:
        saved_results = f.read()
    assert proc.stdout == saved_results, "final_results.txt is not the actual stdout produced by the required command"


def test_entrypoint_handles_unpredictable_inputs_and_multiple_of_seven_edges():
    token = uuid.uuid4().hex
    relative_dir = os.path.join("data", "probe_" + token)
    absolute_dir = os.path.join(ROOT, relative_dir)
    os.makedirs(absolute_dir)

    # Put multiple-of-seven cases between ordinary cases so the verifier also
    # detects persistent logger-version state conflicts after an edge case.
    a = secrets.randbelow(101) - 50
    b = secrets.randbelow(101) - 50
    k = secrets.randbelow(21) - 10
    multiple_values = [a, b, 7 * k - a - b]

    c = secrets.randbelow(101) - 50
    d = secrets.randbelow(101) - 50
    ordinary_values = [c, d, 7 * k + 1 - c - d]

    cases = [
        [secrets.randbelow(30) + 1, secrets.randbelow(30) + 1],
        multiple_values,
        ordinary_values,
        [7, -14, 28],
        [secrets.randbelow(40) + 2, -1, 3],
    ]

    args = []
    expected_lines = []
    for index, values in enumerate(cases):
        relative_path = os.path.join(relative_dir, f"input_{index}_{uuid.uuid4().hex}.txt")
        absolute_path = os.path.join(ROOT, relative_path)
        with open(absolute_path, "w") as f:
            for value in values:
                f.write(f"{value}\n")
        args.append(relative_path)
        expected_lines.append(f"{relative_path}: {sum(values)}")

    proc = subprocess.run(
        [SCRIPT, *args],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert proc.returncode == 0, f"calc_checksums.sh failed on generated inputs: {proc.stderr}"
    assert proc.stdout == "".join(line + "\n" for line in expected_lines), (
        "Generated checksums were incorrect or logging was written to standard output"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
