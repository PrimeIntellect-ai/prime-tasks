#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import subprocess
import random
import csv
import json
import cv2
import numpy as np


def test_video_signal_csv():
    csv_path = "/home/user/video_signal.csv"
    video_path = "/app/experiment_video.mp4"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"File {csv_path} is empty."
        assert header == ["time", "video_val"], f"Invalid header in {csv_path}: {header}"
        rows = list(reader)

    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open {video_path}"
    expected = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        expected.append(float(np.mean(gray[0:50, 0:50])))
    cap.release()

    assert len(rows) == len(expected) == 150, f"Expected exactly 150 rows, found {len(rows)}"
    for idx, (row, expected_val) in enumerate(zip(rows, expected)):
        assert len(row) == 2, f"Invalid row format at index {idx}: {row}"
        try:
            actual_time = float(row[0])
            actual_val = float(row[1])
        except ValueError:
            assert False, f"Non-float values found at index {idx}: {row}"
        assert abs(actual_time - idx / 10.0) < 1e-9, f"Incorrect timestamp at index {idx}: {actual_time}"
        assert abs(actual_val - expected_val) < 1e-6, f"Incorrect video_val at index {idx}: {actual_val} != {expected_val}"


def test_fuzz_equivalence():
    agent_script = "/home/user/fusion_pipeline.py"
    oracle_bin = "/tests/oracle_fusion_pipeline"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_bin), f"Oracle {oracle_bin} does not exist."

    random.seed(42)
    for i in range(100):
        times = [round(x * 0.1, 1) for x in range(501)]
        drop_video = random.sample(range(1, 500), 50)
        video_data = []
        for j, t in enumerate(times):
            if j not in drop_video:
                video_data.append((t, random.uniform(0, 255)))

        num_spikes = random.randint(5, 15)
        for idx in random.sample(range(len(video_data)), num_spikes):
            video_data[idx] = (video_data[idx][0], random.uniform(1000, 2000))

        drop_telemetry = random.sample(range(501), 50)
        telemetry_data = []
        for j, t in enumerate(times):
            if j not in drop_telemetry:
                telemetry_data.append((t, random.uniform(0, 255)))

        video_csv = f"/tmp/fuzz_video_{i}.csv"
        telemetry_csv = f"/tmp/fuzz_telemetry_{i}.csv"
        with open(video_csv, "w") as f:
            f.write("time,video_val\n")
            for t, v in video_data:
                f.write(f"{t},{v}\n")
        with open(telemetry_csv, "w") as f:
            f.write("time,telemetry_val\n")
            for t, v in telemetry_data:
                f.write(f"{t},{v}\n")

        window = random.choice([3, 5, 7, 9])
        threshold = random.uniform(10.0, 50.0)
        agent_out_csv = f"/tmp/agent_out_{i}.csv"
        agent_out_log = f"/tmp/agent_log_{i}.json"
        oracle_out_csv = f"/tmp/oracle_out_{i}.csv"
        oracle_out_log = f"/tmp/oracle_log_{i}.json"

        common = [
            "--video_in", video_csv,
            "--telemetry_in", telemetry_csv,
            "--window", str(window),
            "--threshold", str(threshold),
        ]
        res_agent = subprocess.run(
            [sys.executable, agent_script, *common, "--out_csv", agent_out_csv, "--out_log", agent_out_log],
            capture_output=True, text=True, timeout=30)
        assert res_agent.returncode == 0, f"Agent script failed on run {i}:\n{res_agent.stderr}"

        res_oracle = subprocess.run(
            [sys.executable, oracle_bin, *common, "--out_csv", oracle_out_csv, "--out_log", oracle_out_log],
            capture_output=True, text=True, timeout=30)
        assert res_oracle.returncode == 0, f"Oracle failed on run {i}:\n{res_oracle.stderr}"

        with open(agent_out_csv) as f:
            agent_csv_content = f.read()
        with open(oracle_out_csv) as f:
            oracle_csv_content = f.read()
        assert agent_csv_content == oracle_csv_content, f"CSV output mismatch on run {i}."

        with open(agent_out_log) as f:
            agent_json_content = json.load(f)
        with open(oracle_out_log) as f:
            oracle_json_content = json.load(f)
        assert agent_json_content == oracle_json_content, f"JSON output mismatch on run {i}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
