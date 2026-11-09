#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import subprocess
import struct
import random
import pytest


def test_fuzz_equivalence():
    """Verify the C program behaves bit-exactly identically to the oracle."""
    oracle_path = "/app/oracle_filter"
    agent_path = "/home/user/bayesian_filter"

    assert os.path.isfile(agent_path), f"Agent program {agent_path} not found."
    assert os.access(agent_path, os.X_OK), f"Agent program {agent_path} is not executable."

    with open(agent_path, "rb") as f:
        agent_binary = f.read()
    with open(oracle_path, "rb") as f:
        oracle_binary = f.read()
    assert agent_binary != oracle_binary, "Agent program must not be a byte-identical copy of the oracle."

    random.seed(42)

    for i in range(20):
        num_doubles = random.randint(1, 10000)
        input_data = bytearray()
        for _ in range(num_doubles):
            if random.random() < 0.15:
                val = -999.0
            else:
                val = random.uniform(-1000.0, 1000.0)
            input_data += struct.pack("<d", val)

        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, capture_output=True)

        assert oracle_proc.returncode == 0, "Oracle program failed on valid input."
        assert agent_proc.returncode == 0, f"Agent program failed (return code {agent_proc.returncode}) on fuzz input."

        if oracle_proc.stdout != agent_proc.stdout:
            assert False, f"Agent output does not match oracle output on fuzz input #{i} (length {num_doubles} doubles)."


def expected_measurements_from_video():
    """Decode every video frame as grayscale and calculate its exact mean brightness."""
    probe_proc = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json",
            "/app/stream.mp4",
        ],
        capture_output=True,
        text=True,
    )
    assert probe_proc.returncode == 0, f"ffprobe failed: {probe_proc.stderr}"
    streams = json.loads(probe_proc.stdout).get("streams", [])
    assert streams, "No video stream found in /app/stream.mp4."
    width = int(streams[0]["width"])
    height = int(streams[0]["height"])
    frame_size = width * height
    assert frame_size > 0, "Video has invalid frame dimensions."

    decode_proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", "/app/stream.mp4",
            "-map", "0:v:0", "-vsync", "0", "-f", "rawvideo",
            "-pix_fmt", "gray", "pipe:1",
        ],
        capture_output=True,
    )
    assert decode_proc.returncode == 0, f"ffmpeg failed to decode the video: {decode_proc.stderr.decode(errors='replace')}"
    decoded = decode_proc.stdout
    assert len(decoded) % frame_size == 0, "Decoded video data does not contain complete grayscale frames."

    frame_count = len(decoded) // frame_size
    assert frame_count == 100, f"Expected 100 decoded frames, got {frame_count}."

    values = []
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        brightness = sum(frame) / frame_size
        values.append(-999.0 if brightness < 10.0 else brightness)
    return values


def test_etl_pipeline_files():
    """Verify the generated binary files match the decoded video and oracle behavior."""
    raw_path = "/home/user/raw_measurements.bin"
    smoothed_path = "/home/user/smoothed_measurements.bin"

    assert os.path.isfile(raw_path), f"Raw measurements file {raw_path} not found."
    assert os.path.isfile(smoothed_path), f"Smoothed measurements file {smoothed_path} not found."

    with open(raw_path, "rb") as f:
        raw_data = f.read()

    # The video has 100 frames, so we expect 100 doubles (800 bytes)
    assert len(raw_data) == 800, f"Expected 800 bytes in {raw_path}, got {len(raw_data)} bytes."

    expected_values = expected_measurements_from_video()
    expected_raw_data = b"".join(struct.pack("<d", value) for value in expected_values)
    assert raw_data == expected_raw_data, (
        "The contents of raw_measurements.bin do not match the average grayscale "
        "brightness values decoded from /app/stream.mp4."
    )

    oracle_proc = subprocess.run(["/app/oracle_filter"], input=raw_data, capture_output=True)
    assert oracle_proc.returncode == 0, "Oracle failed on raw measurements."

    with open(smoothed_path, "rb") as f:
        smoothed_data = f.read()

    assert smoothed_data == oracle_proc.stdout, (
        "The contents of smoothed_measurements.bin do not match the expected "
        "output of running raw_measurements.bin through the Bayesian filter."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
