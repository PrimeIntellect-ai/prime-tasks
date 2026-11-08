#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile

import pytest

AGENT_SCRIPT = "/home/user/process_stream.sh"
ORACLE_SCRIPT = "/tests/oracle_process_stream.sh"
SOURCE_VIDEO = "/app/sensor_feed.mp4"


@pytest.fixture(scope="session")
def expected_frames_dir():
    temp_dir = tempfile.mkdtemp(prefix="expected_frames_")
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", SOURCE_VIDEO,
            "-vf", "fps=1",
            os.path.join(temp_dir, "%04d.jpg"),
        ],
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"Could not generate reference frames: {proc.stderr}"
    return temp_dir


def test_frames_extracted(expected_frames_dir):
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist."
    frames = sorted([f for f in os.listdir(frames_dir) if f.endswith('.jpg')])
    assert len(frames) > 0, "No JPEG frames found in the frames directory."

    # Check sequential naming.
    for i, frame in enumerate(frames, start=1):
        expected_name = f"{i:04d}.jpg"
        assert frame == expected_name, f"Expected frame name {expected_name}, got {frame}."

    expected_frames = sorted(
        f for f in os.listdir(expected_frames_dir) if f.endswith(".jpg")
    )
    assert frames == expected_frames, (
        f"Expected exactly {len(expected_frames)} frames extracted at 1 fps, "
        f"but found {len(frames)}."
    )

    # Verify that every submitted JPEG actually depicts its corresponding source frame.
    for frame in frames:
        submitted = os.path.join(frames_dir, frame)
        expected = os.path.join(expected_frames_dir, frame)
        proc = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "info",
                "-i", expected,
                "-i", submitted,
                "-lavfi", "ssim",
                "-f", "null", "-",
            ],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert proc.returncode == 0, f"Frame {frame} is not a valid comparable JPEG."
        match = re.search(r"All:(inf|[0-9.]+)", proc.stderr)
        assert match, f"Could not compare frame {frame} to the source video."
        score = float("inf") if match.group(1) == "inf" else float(match.group(1))
        assert score >= 0.99, (
            f"Frame {frame} does not match the corresponding frame from the source video "
            f"(SSIM {score:.6f})."
        )


def test_raw_sizes_txt():
    raw_sizes_path = "/home/user/raw_sizes.txt"
    frames_dir = "/home/user/frames"
    assert os.path.isfile(raw_sizes_path), f"File {raw_sizes_path} does not exist."

    with open(raw_sizes_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    frames = sorted([f for f in os.listdir(frames_dir) if f.endswith('.jpg')])
    assert len(lines) == len(frames), (
        f"Expected {len(frames)} lines in {raw_sizes_path}, got {len(lines)}."
    )

    for i, frame in enumerate(frames):
        frame_path = os.path.join(frames_dir, frame)
        size = os.path.getsize(frame_path)
        expected_val = "NaN" if size < 5000 else str(size)
        assert lines[i] == expected_val, (
            f"Line {i + 1} in {raw_sizes_path} should be '{expected_val}', got '{lines[i]}'."
        )


def test_processed_metrics_csv():
    processed_path = "/home/user/processed_metrics.csv"
    assert os.path.isfile(processed_path), f"File {processed_path} does not exist."

    raw_sizes_path = "/home/user/raw_sizes.txt"
    with open(raw_sizes_path, "r") as f:
        raw_text = f.read()
    raw_lines = [line.strip() for line in raw_text.splitlines() if line.strip()]

    with open(processed_path, "r") as f:
        processed_text = f.read()
    processed_lines = [line.strip() for line in processed_text.splitlines() if line.strip()]

    assert len(processed_lines) == len(raw_lines), (
        f"Expected {len(raw_lines)} lines in {processed_path}, got {len(processed_lines)}."
    )

    proc = subprocess.run(
        ["bash", AGENT_SCRIPT],
        input=raw_text,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Agent script failed on raw_sizes.txt: {proc.stderr}"
    assert processed_text == proc.stdout, (
        "processed_metrics.csv is not the exact output of process_stream.sh on raw_sizes.txt."
    )

    oracle = subprocess.run(
        ["awk", "-f", ORACLE_SCRIPT],
        input=raw_text,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert oracle.returncode == 0, f"Reference processing failed: {oracle.stderr}"
    assert processed_text == oracle.stdout, "processed_metrics.csv contains incorrect metrics."


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."
    assert os.path.isfile(ORACLE_SCRIPT), "Verification oracle is unavailable."

    with open(AGENT_SCRIPT, "rb") as agent_file, open(ORACLE_SCRIPT, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent script must not be the reference file."

    random.seed(42)
    N = 1000

    for i in range(N):
        num_lines = random.randint(0, 500)
        input_lines = []
        for _ in range(num_lines):
            if random.random() < 0.2:
                input_lines.append("NaN")
            else:
                input_lines.append(str(random.randint(1000, 100000)))

        input_str = "\n".join(input_lines) + ("\n" if input_lines else "")

        oracle_proc = subprocess.run(
            ["awk", "-f", ORACLE_SCRIPT],
            input=input_str,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert oracle_proc.returncode == 0, f"Reference failed: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["bash", AGENT_SCRIPT],
            input=input_str,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on fuzz iteration {i}: {agent_proc.stderr}"
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Fuzz test failed on iteration {i}.\n"
                f"Input:\n{input_str[:200]}...\n"
                f"Expected Output:\n{oracle_out[:200]}...\n"
                f"Agent Output:\n{agent_out[:200]}...\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
