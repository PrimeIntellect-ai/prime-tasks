#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import secrets
import subprocess
import tempfile
import pytest

INPUT_FILE = "/home/user/config_events.txt"
OUTPUT_DIR = "/home/user/output"
SOURCE_FILE = "/home/user/config_tracker.cpp"
PROGRAM_FILE = "/home/user/config_tracker"
LATEST_CONFIGS_FILE = os.path.join(OUTPUT_DIR, "latest_configs.csv")
HOURLY_COUNTS_FILE = os.path.join(OUTPUT_DIR, "hourly_counts.csv")


def normalize_key(key):
    return re.sub(r'[^a-z0-9]', '_', key.lower())


def compute_expected_state(filepath):
    latest_configs = {}
    unique_values = {}
    hourly_counts = {}

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|')
            if len(parts) != 5:
                continue

            ts_str, user, action, key, value = parts
            ts = int(ts_str)
            norm_key = normalize_key(key)
            latest_configs[norm_key] = value
            unique_values.setdefault(norm_key, set()).add(value)
            window = ts - (ts % 3600)
            hourly_counts[window] = hourly_counts.get(window, 0) + 1

    expected_configs = [
        f"{k},{latest_configs[k]},{len(unique_values[k])}"
        for k in sorted(latest_configs.keys())
    ]
    expected_counts = [
        f"{w},{hourly_counts[w]}" for w in sorted(hourly_counts.keys())
    ]
    return expected_configs, expected_counts


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def run_program(program, input_path, output_dir):
    shutil.rmtree(output_dir, ignore_errors=True)
    result = subprocess.run(
        [program, input_path, output_dir],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def assert_outputs(input_path, output_dir):
    latest_path = os.path.join(output_dir, "latest_configs.csv")
    hourly_path = os.path.join(output_dir, "hourly_counts.csv")
    assert os.path.isdir(output_dir), f"Output directory {output_dir} was not created."
    assert os.path.isfile(latest_path), f"File {latest_path} is missing."
    assert os.path.isfile(hourly_path), f"File {hourly_path} is missing."
    expected_configs, expected_counts = compute_expected_state(input_path)
    assert read_nonempty_lines(latest_path) == expected_configs
    assert read_nonempty_lines(hourly_path) == expected_counts


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_submission():
    assert os.path.isfile(SOURCE_FILE), f"Source file {SOURCE_FILE} is missing."
    assert os.path.isfile(PROGRAM_FILE), f"Compiled program {PROGRAM_FILE} is missing."
    assert os.access(PROGRAM_FILE, os.X_OK), f"{PROGRAM_FILE} is not executable."
    with open(PROGRAM_FILE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{PROGRAM_FILE} is not a compiled ELF executable."

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="config_tracker_build_"), "config_tracker")
    compile_result = subprocess.run(
        ["g++", SOURCE_FILE, "-O2", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"{SOURCE_FILE} does not compile.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )

    run_program(PROGRAM_FILE, INPUT_FILE, OUTPUT_DIR)
    return rebuilt


def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} was not created."


def test_latest_configs_csv():
    assert os.path.isfile(LATEST_CONFIGS_FILE), f"File {LATEST_CONFIGS_FILE} is missing."

    expected_configs, _ = compute_expected_state(INPUT_FILE)

    with open(LATEST_CONFIGS_FILE, 'r') as f:
        actual_configs = [line.strip() for line in f if line.strip()]

    assert actual_configs == expected_configs, (
        f"Contents of {LATEST_CONFIGS_FILE} do not match expected.\n"
        f"Expected: {expected_configs}\n"
        f"Actual: {actual_configs}"
    )


def test_hourly_counts_csv():
    assert os.path.isfile(HOURLY_COUNTS_FILE), f"File {HOURLY_COUNTS_FILE} is missing."

    _, expected_counts = compute_expected_state(INPUT_FILE)

    with open(HOURLY_COUNTS_FILE, 'r') as f:
        actual_counts = [line.strip() for line in f if line.strip()]

    assert actual_counts == expected_counts, (
        f"Contents of {HOURLY_COUNTS_FILE} do not match expected.\n"
        f"Expected: {expected_counts}\n"
        f"Actual: {actual_counts}"
    )


def test_programs_on_unseen_input(build_and_execute_submission):
    token_a = secrets.token_hex(12)
    token_b = secrets.token_hex(12)
    token_c = secrets.token_hex(12)
    base = (1700000000 + secrets.randbelow(1000000)) // 3600 * 3600

    work = tempfile.mkdtemp(prefix="config_tracker_case_")
    input_path = os.path.join(work, "events.txt")
    with open(input_path, 'w') as f:
        f.write(f"{base + 5}|u1|CREATE|Alpha.Key|{token_a}\n")
        f.write(f"{base + 61}|u2|UPDATE|ALPHA-KEY|{token_b}\n")
        f.write(f"{base + 3599}|u3|UPDATE|Space Key!|{token_c}\n")
        f.write(f"{base + 3600}|u1|UPDATE|alpha.key|{token_a}\n")
        f.write(f"{base + 7205}|u4|DELETE|Z_9|{token_b}\n")

    submitted_output = os.path.join(work, "submitted_output")
    run_program(PROGRAM_FILE, input_path, submitted_output)
    assert_outputs(input_path, submitted_output)

    rebuilt_output = os.path.join(work, "rebuilt_output")
    run_program(build_and_execute_submission, input_path, rebuilt_output)
    assert_outputs(input_path, rebuilt_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
