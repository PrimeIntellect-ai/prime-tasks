#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"


def get_script_path():
    py_script = "/home/user/filter_data.py"
    sh_script = "/home/user/filter_data.sh"

    if os.path.exists(py_script):
        return py_script
    if os.path.exists(sh_script):
        return sh_script
    return None


def command_for(script_path, *args):
    interpreter = "python3" if script_path.endswith(".py") else "bash"
    return [interpreter, script_path, *args]


def run_validator(script_path, csv_path):
    return subprocess.run(
        command_for(script_path, csv_path),
        capture_output=True,
        timeout=10,
    ).returncode


def test_script_exists():
    script_path = get_script_path()
    assert script_path is not None, "Could not find /home/user/filter_data.py or /home/user/filter_data.sh"
    assert os.path.isfile(script_path), f"{script_path} is not a file"


def test_adversarial_corpus():
    script_path = get_script_path()
    if not script_path:
        pytest.fail("Script not found.")

    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))

    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_DIR}"
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_DIR}"

    clean_failures = []
    evil_failures = []

    for clean_file in clean_files:
        if run_validator(script_path, clean_file) != 0:
            clean_failures.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        if run_validator(script_path, evil_file) == 0:
            evil_failures.append(os.path.basename(evil_file))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def valid_rows(rng):
    rows = []
    statuses = ["OK", "WARNING", "IDLE", "error", "ERROR "]
    for index in range(rng.randint(1, 7)):
        temperature = rng.uniform(-100.0, 45.4999)
        pressure = rng.uniform(0.000001, 10000.0)
        rows.append([
            f"2026-01-{rng.randint(1, 28):02d}T12:34:{index:02d}",
            repr(temperature),
            repr(pressure),
            rng.choice(statuses),
        ])
    return rows


def write_csv(path, rows, header=("timestamp", "temperature", "pressure", "status")):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def test_randomized_hidden_suite_and_cli_contract():
    script_path = get_script_path()
    if not script_path:
        pytest.fail("Script not found.")

    rng = random.Random(secrets.randbits(128))
    cases = []

    with tempfile.TemporaryDirectory(prefix="validation-") as directory:
        # Valid fixtures include exact numerical boundaries and statuses that are
        # not the exact forbidden string.
        for index in range(10):
            rows = valid_rows(rng)
            if index == 0:
                rows[0][1] = "45.5"
                rows[0][2] = "0.000001"
            path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
            write_csv(path, rows)
            cases.append((path, True))

        mutations = [
            lambda row: row.__setitem__(1, repr(rng.uniform(45.500001, 500.0))),
            lambda row: row.__setitem__(2, "0"),
            lambda row: row.__setitem__(2, repr(rng.uniform(-500.0, -0.000001))),
            lambda row: row.__setitem__(3, "ERROR"),
            lambda row: row.__setitem__(1, ""),
            lambda row: row.__setitem__(2, ""),
            lambda row: row.__setitem__(rng.choice([1, 2]), rng.choice(["NaN", "nan", "null"])),
            lambda row: row.__setitem__(rng.choice([1, 2]), rng.choice(["abc", "1.2.3", "--5"])),
        ]

        for mutation in mutations:
            for _ in range(6):
                rows = valid_rows(rng)
                mutation(rows[rng.randrange(len(rows))])
                path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
                write_csv(path, rows)
                cases.append((path, False))

        # Structurally malformed files use randomized names in the same directory
        # as valid files, so path-based classification cannot pass.
        for index in range(6):
            path = os.path.join(directory, f"{uuid.uuid4().hex}.csv")
            rows = valid_rows(rng)
            if index % 2 == 0:
                write_csv(path, rows, header=("timestamp", "temperature", "pressure", "wrong_status"))
            else:
                write_csv(path, rows)
                with open(path, "a", encoding="utf-8") as handle:
                    handle.write("too,few,columns\n")
            cases.append((path, False))

        rng.shuffle(cases)
        failures = []
        for path, should_accept in cases:
            returncode = run_validator(script_path, path)
            accepted = returncode == 0
            if accepted != should_accept:
                failures.append((os.path.basename(path), should_accept, returncode))

        assert not failures, f"Randomized validation failures: {failures[:10]}"

        sample_path = cases[0][0]
        no_arg = subprocess.run(command_for(script_path), capture_output=True, timeout=10)
        extra_arg = subprocess.run(
            command_for(script_path, sample_path, sample_path),
            capture_output=True,
            timeout=10,
        )
        assert no_arg.returncode != 0, "Validator must reject invocation without a CSV argument"
        assert extra_arg.returncode != 0, "Validator must accept exactly one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
