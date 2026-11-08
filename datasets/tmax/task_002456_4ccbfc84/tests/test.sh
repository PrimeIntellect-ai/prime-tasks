#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess
import pytest

AGENT_PATH = "/home/user/bin/infer"
SOURCE_PATH = "/home/user/infer.go"
OUTPUT_PATH = "/home/user/video_scene_changes.json"
VIDEO_PATH = "/app/data/traffic_cam.mp4"
WEIGHTS_PATH = "/app/data/weights.csv"
BIASES_PATH = "/app/data/biases.csv"


def load_model():
    with open(WEIGHTS_PATH, newline="") as f:
        weights = [[float(x) for x in row] for row in csv.reader(f)]
    with open(BIASES_PATH, newline="") as f:
        bias_rows = [[float(x) for x in row] for row in csv.reader(f)]

    assert len(weights) == 16
    assert all(len(row) == 8 for row in weights)
    assert len(bias_rows) == 1 and len(bias_rows[0]) == 8
    return weights, bias_rows[0]


WEIGHTS, BIASES = load_model()


def reference_infer(frames):
    changes = []
    previous = None

    for index, frame in enumerate(frames):
        assert len(frame) == 16
        embedding = []
        for j in range(8):
            value = BIASES[j]
            for k in range(16):
                value += float(frame[k]) * WEIGHTS[k][j]
            embedding.append(max(0.0, value))

        if previous is not None:
            dot = sum(embedding[j] * previous[j] for j in range(8))
            norm1 = sum(value * value for value in embedding)
            norm2 = sum(value * value for value in previous)
            if norm1 == 0.0 or norm2 == 0.0:
                similarity = 1.0
            else:
                similarity = dot / (math.sqrt(norm1) * math.sqrt(norm2))
            if similarity < 0.8000:
                changes.append(index)

        previous = embedding

    return changes


def run_agent(frames):
    proc = subprocess.run(
        [AGENT_PATH],
        input=json.dumps(frames),
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode == 0, f"Agent failed. Stderr: {proc.stderr}"
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Agent output is not valid JSON: {proc.stdout!r}")
    assert isinstance(result, list), "Agent output must be a JSON array"
    assert all(type(item) is int for item in result), "Agent output must contain integer indices"
    return result


def extract_video_frames():
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-vf", "fps=1,scale=4:4,format=gray",
            "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1",
        ],
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"ffmpeg failed: {proc.stderr.decode(errors='replace')}"
    assert len(proc.stdout) > 0, "ffmpeg extracted no frames"
    assert len(proc.stdout) % 16 == 0, "Unexpected raw frame byte count"
    return [list(proc.stdout[i:i + 16]) for i in range(0, len(proc.stdout), 16)]


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable missing: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable not executable: {AGENT_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Go source missing: {SOURCE_PATH}"


def test_video_scene_changes_json_exists_and_valid():
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON missing: {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON")

    assert isinstance(data, list), "Output must be a JSON array"
    assert all(type(item) is int for item in data), "Output must contain integer indices"

    frames = extract_video_frames()
    expected = reference_infer(frames)
    actual_program_output = run_agent(frames)
    assert data == actual_program_output, "Saved output does not match infer output for the video frames"
    assert data == expected, f"Incorrect scene changes for traffic_cam.mp4: expected {expected}, got {data}"


def test_fuzz_equivalence():
    random.seed(42)
    N = 500

    for i in range(N):
        outer_length = random.randint(10, 100)
        input_data = [
            [random.uniform(0.0, 255.0) for _ in range(16)]
            for _ in range(outer_length)
        ]
        expected = reference_infer(input_data)
        actual = run_agent(input_data)
        assert actual == expected, (
            f"Mismatch on input {i}.\n"
            f"Input: {json.dumps(input_data)}\n"
            f"Expected output: {expected}\n"
            f"Agent output: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
