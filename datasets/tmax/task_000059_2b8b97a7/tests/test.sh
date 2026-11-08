#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import glob
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/validate_logs.sh"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
VIDEO_PATH = "/app/data/conveyor.mp4"


def run_validator(path):
    return subprocess.run(
        [SCRIPT_PATH, path],
        capture_output=True,
        timeout=15,
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}"

    clean_failed = []
    evil_bypassed = []

    for clean_file in clean_files:
        result = run_validator(clean_file)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        result = run_validator(evil_file)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    error_messages = []
    if clean_failed:
        error_messages.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): "
            f"{', '.join(clean_failed)}"
        )
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): "
            f"{', '.join(evil_bypassed)}"
        )

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def video_frame_count():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-count_frames", "-show_entries", "stream=nb_read_frames",
            "-of", "default=nokey=1:noprint_wrappers=1", VIDEO_PATH,
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    count = int(result.stdout.strip())
    assert count > 2
    return count


def test_generated_and_mutated_inputs():
    n = video_frame_count()
    rng = secrets.SystemRandom()
    step_us = rng.randrange(1000, 90000)
    offset_us = rng.randrange(0, 1000000)

    rows = []
    for frame in range(1, n + 1):
        micros = offset_us + frame * step_us
        timestamp = f"{micros // 1000000}.{micros % 1000000:06d}"
        event = f"0x{rng.randrange(65536):04X}"
        rows.append([str(frame), timestamp, event])

    header = "frame,timestamp_sec,event_code"
    cases = []

    def add_case(name, expected_valid, case_rows=None, case_header=header):
        cases.append((name, expected_valid, case_header,
                      copy.deepcopy(rows if case_rows is None else case_rows)))

    add_case("valid randomized CSV", True)
    add_case("one data row missing", False, rows[:-1])

    extra_rows = copy.deepcopy(rows)
    next_micros = offset_us + (n + 1) * step_us
    extra_rows.append([
        str(n + 1),
        f"{next_micros // 1000000}.{next_micros % 1000000:06d}",
        f"0x{rng.randrange(65536):04X}",
    ])
    add_case("one extra data row", False, extra_rows)
    add_case("incorrect header", False, case_header="frame,timestamp,event_code")

    changed = copy.deepcopy(rows)
    changed[0][0] = "0"
    add_case("frame sequence starts at zero", False, changed)

    pos = rng.randrange(1, n - 1)
    changed = copy.deepcopy(rows)
    changed[pos][0] = changed[pos - 1][0]
    add_case("duplicate frame in sequence", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos][1] = changed[pos - 1][1]
    add_case("equal adjacent timestamps", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos][1] = "not-a-number"
    add_case("nonnumeric timestamp", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos][2] = "0x12af"
    add_case("lowercase hexadecimal event", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos][2] = "0x123"
    add_case("short hexadecimal event", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos][2] = "1234"
    add_case("event without prefix", False, changed)

    changed = copy.deepcopy(rows)
    changed[pos].append("unexpected")
    add_case("extra CSV field", False, changed)

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="csvcheck_") as temp_dir:
        # Every generated case uses the same neutral path, so classification by
        # clean/evil directory or filename cannot satisfy these checks.
        candidate = os.path.join(temp_dir, "input.csv")
        for name, expected_valid, case_header, case_rows in cases:
            with open(candidate, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(case_header + "\n")
                for row in case_rows:
                    handle.write(",".join(row) + "\n")

            result = run_validator(candidate)
            if expected_valid:
                assert result.returncode == 0, (
                    f"Validator rejected {name}; exit status {result.returncode}"
                )
            else:
                assert result.returncode != 0, f"Validator accepted {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
