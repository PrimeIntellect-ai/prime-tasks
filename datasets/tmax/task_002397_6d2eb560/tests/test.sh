#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/validate_config.sh"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
VIDEO_PATH = "/app/dashboard.mp4"


def run_validator(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on {path}")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_modified = []
    evil_bypassed = []

    for clean_file in clean_files:
        result = run_validator(clean_file)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        result = run_validator(evil_file)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def extract_reset_frames():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", VIDEO_PATH,
        ],
        capture_output=True, check=True, timeout=15,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    frame_size = width * height * 3

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-map", "0:v:0", "-vsync", "0", "-f", "rawvideo",
            "-pix_fmt", "rgb24", "pipe:1",
        ],
        capture_output=True, check=True, timeout=30,
    ).stdout
    assert len(decoded) >= frame_size and len(decoded) % frame_size == 0

    reset_frames = set()
    frame_count = len(decoded) // frame_size
    for index in range(frame_count):
        frame = decoded[index * frame_size:(index + 1) * frame_size]
        red = frame[0::3]
        green = frame[1::3]
        blue = frame[2::3]
        # H.264/YUV conversion can shift nominal 255 slightly, so require every
        # pixel to remain uniformly and overwhelmingly red.
        if min(red) >= 240 and max(green) <= 15 and max(blue) <= 15:
            reset_frames.add(index)

    assert reset_frames, "No reset frames were found in the dashboard video"
    return reset_frames, frame_count


def oracle_valid(rows, reset_times):
    cpu_window = []
    for row in rows:
        cpu = int(row["cpu_limit"])
        mem = int(row["mem_limit"])
        net = int(row["net_limit"])

        if cpu > 100 or mem > 100 or net > 100:
            return False

        cpu_window.append(cpu)
        cpu_window = cpu_window[-3:]
        if Decimal(sum(cpu_window)) / Decimal(len(cpu_window)) > Decimal("80.00"):
            return False

        if Decimal(row["timestamp"]) in reset_times and mem != 0:
            return False

    return True


def make_valid_rows(rng, reset_frames, frame_count):
    row_count = rng.randrange(3, 9)
    chosen_reset = rng.choice(tuple(reset_frames))
    timestamps = {Decimal(chosen_reset) / Decimal(10)}

    # Hundredth-second values include both frame-aligned and non-frame-aligned
    # timestamps, preventing approximate timestamp matching from being accepted.
    while len(timestamps) < row_count:
        timestamps.add(Decimal(rng.randrange(0, frame_count * 10)) / Decimal(100))

    reset_times = {Decimal(i) / Decimal(10) for i in reset_frames}
    rows = []
    for timestamp in sorted(timestamps):
        rows.append({
            "timestamp": format(timestamp, "f"),
            "cpu_limit": str(rng.randrange(0, 81)),
            "mem_limit": "0" if timestamp in reset_times else str(rng.randrange(0, 101)),
            "net_limit": str(rng.randrange(0, 101)),
        })
    return rows


def clone_rows(rows):
    return [dict(row) for row in rows]


def test_generated_cases_against_recomputed_rules():
    reset_frames, frame_count = extract_reset_frames()
    reset_times = {Decimal(i) / Decimal(10) for i in reset_frames}
    rng = secrets.SystemRandom()
    cases = []

    for _ in range(12):
        rows = make_valid_rows(rng, reset_frames, frame_count)
        cases.append(rows)

    for _ in range(4):
        rows = make_valid_rows(rng, reset_frames, frame_count)
        bad = clone_rows(rows)
        metric = rng.choice(["cpu_limit", "mem_limit", "net_limit"])
        bad[rng.randrange(len(bad))][metric] = str(rng.randrange(101, 151))
        cases.append(bad)

    for _ in range(4):
        rows = make_valid_rows(rng, reset_frames, frame_count)
        bad = clone_rows(rows)
        bad[0]["cpu_limit"] = "81"
        cases.append(bad)

    for _ in range(4):
        rows = make_valid_rows(rng, reset_frames, frame_count)
        bad = clone_rows(rows)
        reset_indexes = [
            i for i, row in enumerate(bad)
            if Decimal(row["timestamp"]) in reset_times
        ]
        assert reset_indexes
        bad[rng.choice(reset_indexes)]["mem_limit"] = str(rng.randrange(1, 101))
        cases.append(bad)

    evaluated = [(rows, oracle_valid(rows, reset_times)) for rows in cases]
    assert any(expected for _, expected in evaluated)
    assert any(not expected for _, expected in evaluated)
    rng.shuffle(evaluated)

    # Every generated case uses the same neutral path, so validity cannot be
    # inferred from directory or filename.
    with tempfile.TemporaryDirectory(prefix="cfgcheck_") as temp_dir:
        candidate = os.path.join(temp_dir, "candidate.csv")
        for rows, expected_valid in evaluated:
            with open(candidate, "w", newline="") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=["timestamp", "cpu_limit", "mem_limit", "net_limit"],
                )
                writer.writeheader()
                writer.writerows(rows)

            result = run_validator(candidate)
            expected_code = 0 if expected_valid else 1
            assert result.returncode == expected_code, (
                f"Expected exit {expected_code}, got {result.returncode} for generated CSV; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
