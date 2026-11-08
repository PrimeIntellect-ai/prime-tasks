#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import filecmp
import math
import os
import random
import re
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

VIDEO_PATH = "/app/experiment_video.mp4"
SENSOR_PATH = "/app/sensor_data.csv"
VIDEO_CSV = "/home/user/video_stats.csv"
JOINED_CSV = "/home/user/joined_dataset.csv"
AGENT_SOURCE = "/home/user/join_stats.c"
AGENT_BIN = "/home/user/join_stats"
ORACLE_BIN = "/app/oracle_join_stats"
MODEL_RESULT = "/home/user/model_result.txt"


def expected_video_rows():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    rows = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        else:
            gray = frame
        rows.append([str(index), str(index * 40), f"{float(np.mean(gray)):.2f}"])
        index += 1
    cap.release()
    assert len(rows) == 1500, f"Verifier decoded {len(rows)} frames instead of 1500"
    return rows


def read_csv(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def expected_join_rows(video_rows):
    sensor_rows = read_csv(SENSOR_PATH)
    assert sensor_rows and sensor_rows[0] == ["timestamp_ms", "sensor_value"]

    first_sensor = {}
    for row in sensor_rows[1:]:
        assert len(row) == 2
        first_sensor.setdefault(row[0], row[1])

    result = []
    seen = set()
    for row in video_rows:
        ts = row[1]
        if ts in seen:
            continue
        seen.add(ts)
        if ts in first_sensor:
            result.append([ts, row[2], first_sensor[ts]])
    return result


def test_video_stats_csv():
    assert os.path.isfile(VIDEO_CSV), f"Missing {VIDEO_CSV}"
    actual = read_csv(VIDEO_CSV)
    assert actual, "video_stats.csv is empty"
    assert actual[0] == ["frame_index", "timestamp_ms", "avg_brightness"], "Incorrect headers in video_stats.csv"
    assert len(actual[1:]) == 1500, f"Expected 1500 rows in video_stats.csv, found {len(actual[1:])}"

    expected = expected_video_rows()
    assert actual[1:] == expected, "video_stats.csv does not contain the decoded per-frame indices, timestamps, and average grayscale brightness values"


def test_joined_dataset_csv():
    assert os.path.isfile(JOINED_CSV), f"Missing {JOINED_CSV}"
    actual = read_csv(JOINED_CSV)
    assert actual, "joined_dataset.csv is empty"
    assert actual[0] == ["timestamp_ms", "avg_brightness", "sensor_value"], "Incorrect headers in joined_dataset.csv"

    video_rows = expected_video_rows()
    expected = expected_join_rows(video_rows)
    assert actual[1:] == expected, "joined_dataset.csv is not the required inner join of video_stats.csv and sensor_data.csv"

    assert os.path.isfile(AGENT_BIN), f"Missing agent binary at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    proc = subprocess.run(
        [AGENT_BIN, VIDEO_CSV, SENSOR_PATH],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, "join_stats failed on the experiment inputs"
    expected_output_lines = [",".join(row) for row in expected]
    assert proc.stdout.splitlines() == expected_output_lines, "join_stats output on the experiment inputs is incorrect"
    assert actual[1:] == [line.split(",") for line in proc.stdout.splitlines()], "joined_dataset.csv was not produced from join_stats output"


def test_model_result():
    assert os.path.isfile(MODEL_RESULT), f"Missing {MODEL_RESULT}"
    with open(MODEL_RESULT, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[+-]?\d+\.\d{4}", content), "model_result.txt must contain one finite coefficient rounded to exactly four decimal places"
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {MODEL_RESULT} is not a valid float: {content}")
    assert math.isfinite(value), "model_result.txt must contain a finite float"

    joined = expected_join_rows(expected_video_rows())
    x = np.asarray([float(row[1]) for row in joined], dtype=float)
    y = np.asarray([float(row[2]) for row in joined], dtype=float)
    expected_slope = float(np.sum((x - x.mean()) * (y - y.mean())) / np.sum((x - x.mean()) ** 2))
    assert content == f"{expected_slope:.4f}", f"Incorrect OLS slope: expected {expected_slope:.4f}, got {content}"


def test_join_stats_fuzz_equivalence():
    assert os.path.isfile(AGENT_SOURCE), f"Missing C source at {AGENT_SOURCE}"
    assert os.path.getsize(AGENT_SOURCE) > 0, f"C source at {AGENT_SOURCE} is empty"
    assert os.path.isfile(AGENT_BIN), f"Missing agent binary at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    assert os.path.isfile(ORACLE_BIN), f"Missing oracle binary at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable"
    assert not filecmp.cmp(AGENT_BIN, ORACLE_BIN, shallow=False), "Agent binary must not be a byte-identical copy of the oracle"

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_bin = os.path.join(tmpdir, "join_stats_from_source")
        build = subprocess.run(
            ["gcc", "-O2", AGENT_SOURCE, "-o", rebuilt_bin],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"join_stats.c did not compile:\n{build.stderr}"

        csv1_path = os.path.join(tmpdir, "csv1.csv")
        csv2_path = os.path.join(tmpdir, "csv2.csv")
        random.seed(42)
        N = 500

        for i in range(N):
            num_rows_1 = random.randint(0, 500)
            num_rows_2 = random.randint(0, 500)

            with open(csv1_path, "w", encoding="utf-8") as f1:
                f1.write("frame_index,timestamp_ms,avg_brightness\n")
                for r in range(num_rows_1):
                    ts = random.randint(0, 1000) * 40
                    f1.write(f"{r},{ts},{random.uniform(0, 255):.2f}\n")

            with open(csv2_path, "w", encoding="utf-8") as f2:
                f2.write("timestamp_ms,sensor_value\n")
                for r in range(num_rows_2):
                    ts = random.randint(0, 1000) * 40
                    f2.write(f"{ts},{random.uniform(-10, 10):.4f}\n")

            oracle_proc = subprocess.run(
                [ORACLE_BIN, csv1_path, csv2_path],
                capture_output=True,
                text=True,
                timeout=20,
            )

            for candidate_name, candidate_bin in (("installed binary", AGENT_BIN), ("binary rebuilt from join_stats.c", rebuilt_bin)):
                agent_proc = subprocess.run(
                    [candidate_bin, csv1_path, csv2_path],
                    capture_output=True,
                    text=True,
                    timeout=20,
                )

                if oracle_proc.returncode != agent_proc.returncode or oracle_proc.stdout != agent_proc.stdout:
                    with open(csv1_path, "r", encoding="utf-8") as f:
                        csv1_content = f.read()
                    with open(csv2_path, "r", encoding="utf-8") as f:
                        csv2_content = f.read()
                    pytest.fail(
                        f"Fuzz equivalence failed for {candidate_name} on iteration {i}.\n"
                        f"CSV 1:\n{csv1_content[:500]}...\n"
                        f"CSV 2:\n{csv2_content[:500]}...\n"
                        f"Oracle Return Code: {oracle_proc.returncode}\n"
                        f"Agent Return Code: {agent_proc.returncode}\n"
                        f"Oracle Output (first 500 chars):\n{oracle_proc.stdout[:500]}\n"
                        f"Agent Output (first 500 chars):\n{agent_proc.stdout[:500]}\n"
                    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
