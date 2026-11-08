#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import numpy as np
import pandas as pd

SCRIPT = "/home/user/run_pipeline.sh"
SOURCE = "/home/user/etl_processor.c"
REPORT = "/home/user/traffic_report.csv"
VIDEO = "/app/traffic.mp4"


def expected_rows():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO, "-f", "rawvideo", "-pix_fmt", "gray", "-vcodec", "rawvideo", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=120,
    )
    frame_size = 320 * 240
    assert len(result.stdout) % frame_size == 0, "Decoded stream contains a partial frame"
    frames = np.frombuffer(result.stdout, dtype=np.uint8).reshape(-1, 240, 320)

    scores = np.zeros(len(frames), dtype=np.float64)
    for i in range(1, len(frames)):
        scores[i] = np.abs(frames[i].astype(np.int16) - frames[i - 1].astype(np.int16)).mean()

    rows = []
    for start in range(0, len(scores), 25):
        window = scores[start:start + 25]
        if len(window) != 25:
            continue
        avg = float(window.mean())
        lik0 = math.exp(-0.5 * ((avg - 2.0) / 1.5) ** 2) / (1.5 * math.sqrt(2.0 * math.pi))
        lik1 = math.exp(-0.5 * ((avg - 15.0) / 5.0) ** 2) / (5.0 * math.sqrt(2.0 * math.pi))
        posterior = (0.3 * lik1) / (0.3 * lik1 + 0.7 * lik0)
        rows.append((start // 25, avg, round(posterior, 4)))
    return rows


def validate_report(expected, label):
    assert os.path.isfile(REPORT), f"Agent output CSV is missing after {label}: {REPORT}"
    assert not os.path.islink(REPORT), "Agent output CSV must be a regular file, not a symlink"

    with open(REPORT, newline="") as f:
        reader = csv.reader(f)
        raw_rows = list(reader)
    assert raw_rows, "Agent CSV is empty"
    assert raw_rows[0] == ["window_id", "avg_motion", "p_congested"], \
        "CSV header must be exactly window_id,avg_motion,p_congested"
    assert len(raw_rows) == len(expected) + 1, "CSV must contain exactly one row per complete 25-frame window"

    for row in raw_rows[1:]:
        assert len(row) == 3, "Every CSV row must contain exactly three fields"
        assert re.fullmatch(r"(?:0|1)\.\d{4}", row[2].strip()), \
            "p_congested values must be formatted to exactly 4 decimal places"

    try:
        df_agent = pd.read_csv(REPORT)
    except Exception as exc:
        raise AssertionError(f"Failed to read agent CSV: {exc}")

    assert "window_id" in df_agent.columns, "Agent CSV missing 'window_id' column"
    assert "avg_motion" in df_agent.columns, "Agent CSV missing 'avg_motion' column"
    assert "p_congested" in df_agent.columns, "Agent CSV missing 'p_congested' column"
    assert not df_agent["window_id"].duplicated().any(), "window_id values must be unique"

    expected_ids = [row[0] for row in expected]
    actual_ids = df_agent["window_id"].tolist()
    assert actual_ids == expected_ids, f"Expected window_ids {expected_ids}, got {actual_ids}"

    actual_avg = pd.to_numeric(df_agent["avg_motion"], errors="coerce").to_numpy(dtype=float)
    actual_prob = pd.to_numeric(df_agent["p_congested"], errors="coerce").to_numpy(dtype=float)
    expected_avg = np.array([row[1] for row in expected], dtype=float)
    expected_prob = np.array([row[2] for row in expected], dtype=float)

    assert np.isfinite(actual_avg).all(), "avg_motion contains non-finite or non-numeric values"
    assert np.isfinite(actual_prob).all(), "p_congested contains non-finite or non-numeric values"
    assert np.allclose(actual_avg, expected_avg, rtol=0.0, atol=1e-4), "avg_motion values are inaccurate"

    mae = np.mean(np.abs(actual_prob - expected_prob))
    threshold = 0.01
    assert mae <= threshold, \
        f"MAE of p_congested is {mae:.5f}, which exceeds the maximum acceptable threshold of {threshold}"


def test_pipeline_and_c_processor():
    assert os.path.isfile(SCRIPT), f"Pipeline script is missing: {SCRIPT}"
    assert not os.path.islink(SCRIPT), "Pipeline script must be a regular file, not a symlink"

    if os.path.exists(REPORT):
        os.remove(REPORT)
    completed = subprocess.run(
        ["bash", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300
    )
    assert completed.returncode == 0, \
        f"Pipeline script failed with exit code {completed.returncode}:\n{completed.stderr[-4000:]}"

    assert os.path.isfile(SOURCE), f"C source is missing after running the pipeline: {SOURCE}"
    assert not os.path.islink(SOURCE), "C source must be a regular file, not a symlink"

    with open(SCRIPT, "r", errors="replace") as f:
        script_text = f.read()
    assert "ffmpeg" in script_text, "Pipeline script does not invoke ffmpeg"
    assert re.search(r"\b(?:gcc|cc|clang|make)\b", script_text), "Pipeline script does not compile the C program"

    expected = expected_rows()
    validate_report(expected, "running run_pipeline.sh")

    verifier_binary = "/tmp/etl_processor_verifier"
    compiled = subprocess.run(
        ["gcc", "-O2", "-std=c11", SOURCE, "-o", verifier_binary, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert compiled.returncode == 0, f"etl_processor.c failed to compile:\n{compiled.stderr[-4000:]}"

    os.remove(REPORT)
    exercised = subprocess.run(
        ["bash", "-o", "pipefail", "-c",
         f"ffmpeg -v error -i {VIDEO} -f rawvideo -pix_fmt gray -vcodec rawvideo - | {verifier_binary}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert exercised.returncode == 0, \
        f"Independently compiled C processor failed on the decoded stream:\n{exercised.stderr[-4000:]}"
    validate_report(expected, "independently compiling and exercising etl_processor.c")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
