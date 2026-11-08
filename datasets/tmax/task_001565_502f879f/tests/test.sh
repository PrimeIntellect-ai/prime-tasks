#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess

import pytest

AGENT_SOURCE = "/home/user/etl_cleaner.go"
AGENT_EXECUTABLE = "/home/user/etl_cleaner"
OUTPUT_FILE = "/home/user/cleaned_video_data.txt"
VIDEO_FILE = "/app/etl_stream.mp4"
FUZZ_N = 50


def align_timestamp(timestamp):
    scaled = timestamp * 2.0
    if scaled < 0:
        rounded = math.ceil(scaled - 0.5)
    else:
        rounded = math.floor(scaled + 0.5)
    aligned = rounded / 2.0
    if rounded == 0 and timestamp < 0:
        aligned = -0.0
    return aligned


def expected_cleaner_output(input_data):
    records = {}

    for line in input_data.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(",")
        if len(parts) != 4:
            continue

        timestamp = float(parts[0])
        size = int(parts[1])
        typ = parts[2].lower()
        retry_id = int(parts[3])
        aligned = align_timestamp(timestamp)
        key = (format(aligned, ".1f"), typ)
        candidate = (aligned, typ, size, retry_id)

        existing = records.get(key)
        if existing is None or retry_id > existing[3] or (
            retry_id == existing[3] and size > existing[2]
        ):
            records[key] = candidate

    ordered = sorted(records.values(), key=lambda r: (r[0], r[1]))
    return "".join(
        f"{aligned:.1f}|{typ}|{size}|{retry_id}\n"
        for aligned, typ, size, retry_id in ordered
    )


def run_agent(input_data):
    return subprocess.run(
        [AGENT_EXECUTABLE],
        input=input_data,
        text=True,
        capture_output=True,
        check=True,
        timeout=5,
    ).stdout


def generate_fuzz_input():
    num_lines = random.randint(10, 500)
    lines = []
    types = ["I", "P", "B", "i", "p", "b", "IDR"]
    for _ in range(num_lines):
        timestamp = random.uniform(0.0, 100.0)
        size = random.randint(100, 10000)
        typ = random.choice(types)
        retry_id = random.randint(1, 5)
        lines.append(f"{timestamp:.4f},{size},{typ},{retry_id}")
    return "\n".join(lines) + "\n"


def video_csv_from_ffprobe():
    proc = subprocess.run(
        [
            "ffprobe",
            "-v", "error",
            "-select_streams", "v:0",
            "-show_frames",
            "-show_entries", "frame=pkt_pts_time,pkt_size,pict_type",
            "-of", "json",
            VIDEO_FILE,
        ],
        text=True,
        capture_output=True,
        check=True,
        timeout=30,
    )
    frames = json.loads(proc.stdout).get("frames", [])
    assert frames, "ffprobe returned no frames for the first video stream."

    lines = []
    for index, frame in enumerate(frames):
        missing = [
            field for field in ("pkt_pts_time", "pkt_size", "pict_type")
            if field not in frame
        ]
        assert not missing, (
            f"Frame {index} is missing requested ffprobe fields: {missing}"
        )
        lines.append(
            f"{frame['pkt_pts_time']},{frame['pkt_size']},{frame['pict_type']},1"
        )
    return "\n".join(lines) + "\n"


def test_agent_artifacts_exist_and_source_builds():
    assert os.path.isfile(AGENT_SOURCE), f"Go source {AGENT_SOURCE} not found."
    assert os.path.isfile(AGENT_EXECUTABLE), (
        f"Agent executable {AGENT_EXECUTABLE} not found or is not a regular file."
    )
    assert os.access(AGENT_EXECUTABLE, os.X_OK), (
        f"Agent executable {AGENT_EXECUTABLE} is not executable."
    )
    subprocess.run(
        ["go", "build", "-o", "/tmp/verified_etl_cleaner", AGENT_SOURCE],
        text=True,
        capture_output=True,
        check=True,
        timeout=30,
    )


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} not found."
    assert os.path.getsize(OUTPUT_FILE) > 0, f"Output file {OUTPUT_FILE} is empty."


def test_deterministic_pipeline_cases():
    input_data = (
        "1.24,4096,I,2\n"
        "1.25,100,P,1\n"
        "1.74,200,p,3\n"
        "1.70,300,P,3\n"
        "2.26,500,IDR,1\n"
        "2.24,600,idr,1\n"
        "3.00,700,B,4\n"
        "3.01,800,b,4\n"
        "3.02,800,B,4\n"
    )
    assert run_agent(input_data) == expected_cleaner_output(input_data)


def test_fuzz_equivalence():
    random.seed(42)
    for i in range(FUZZ_N):
        input_data = generate_fuzz_input()
        try:
            agent_out = run_agent(input_data)
        except subprocess.CalledProcessError as exc:
            pytest.fail(
                f"Agent program failed on fuzz iteration {i}.\n"
                f"Input:\n{input_data}\nStderr:\n{exc.stderr}"
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on fuzz iteration {i}.")

        expected = expected_cleaner_output(input_data)
        if agent_out != expected:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"Input (first 5 lines):\n"
                f"{chr(10).join(input_data.splitlines()[:5])}\n...\n"
                f"Expected Output:\n{expected}\n"
                f"Agent Output:\n{agent_out}\n"
            )


def test_cleaned_video_data_semantics():
    generated_csv = video_csv_from_ffprobe()
    expected = expected_cleaner_output(generated_csv)
    assert expected, "Expected cleaned video metadata is unexpectedly empty."

    with open(OUTPUT_FILE, "r", encoding="utf-8") as output_handle:
        actual = output_handle.read()

    assert actual == expected, (
        "cleaned_video_data.txt is not the result of processing the requested "
        "ffprobe frame metadata through the cleaner."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
