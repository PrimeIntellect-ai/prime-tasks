#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import tempfile

import pytest

AGENT_SCRIPT = "/home/user/query_range.sh"
VIDEO = "/app/drone_feed.mp4"
TELEMETRY = "/home/user/data/telemetry.csv"


def build_expected_data():
    frame_dir = tempfile.mkdtemp(prefix="verifier_frames_")
    frame_pattern = os.path.join(frame_dir, "frame_%03d.jpg")
    result = subprocess.run(
        ["ffmpeg", "-i", VIDEO, "-vf", "fps=1", frame_pattern, "-loglevel", "quiet"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Verifier frame extraction failed: {result.stderr}"

    frame_sizes = {}
    for second in range(1, 121):
        path = os.path.join(frame_dir, f"frame_{second:03d}.jpg")
        assert os.path.isfile(path), f"Expected extracted frame is missing: {path}"
        frame_sizes[second] = os.path.getsize(path)

    observed = {}
    with open(TELEMETRY, newline="") as telemetry_file:
        reader = csv.DictReader(telemetry_file)
        for row in reader:
            observed[int(row["timestamp"])] = float(row["speed"])

    speeds = {}
    last_speed = 0.0
    for second in range(1, 121):
        if second in observed:
            last_speed = observed[second]
        speeds[second] = last_speed

    return speeds, frame_sizes


SPEEDS, FRAME_SIZES = build_expected_data()


def expected_output(start_sec, end_sec):
    seconds = range(start_sec, end_sec + 1)
    average = sum(SPEEDS[second] for second in seconds) / (end_sec - start_sec + 1)
    maximum = max(FRAME_SIZES[second] for second in seconds)
    return f"AverageSpeed: {average:.1f} | MaxFrameSize: {maximum}"


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."


def test_fuzz_equivalence():
    random.seed(42)

    for _ in range(200):
        a = random.randint(1, 120)
        b = random.randint(1, 120)
        start_sec = min(a, b)
        end_sec = max(a, b)
        expected = expected_output(start_sec, end_sec)

        agent_res = subprocess.run(
            [AGENT_SCRIPT, str(start_sec), str(end_sec)],
            capture_output=True,
            text=True,
        )
        agent_out = agent_res.stdout.strip()

        if agent_res.returncode != 0:
            pytest.fail(
                f"Agent script failed on input '{start_sec} {end_sec}'.\n"
                f"Stderr: {agent_res.stderr}"
            )

        if expected != agent_out:
            pytest.fail(
                f"Mismatch on input: {start_sec} {end_sec}\n"
                f"Expected:    {expected}\n"
                f"Got (Agent): {agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
