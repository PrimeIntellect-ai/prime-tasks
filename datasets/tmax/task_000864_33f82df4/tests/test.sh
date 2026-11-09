#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import shlex
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

FILTER_SCRIPT = "/home/user/filter_telemetry.py"
VIDEO_SCRIPT = "/home/user/process_video.py"
VIDEO_PATH = "/app/traffic.mp4"
CSV_PATH = "/home/user/video_stats.csv"


def run_filter(path):
    result = subprocess.run(
        ["python3", FILTER_SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    records = []
    for line in result.stdout.splitlines():
        if line.strip():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                pytest.fail(f"Sanitizer emitted invalid JSON: {line!r}: {exc}")
    return records


def test_telemetry_sanitizer_clean_corpus():
    assert os.path.exists(FILTER_SCRIPT), f"Script missing at {FILTER_SCRIPT}"
    assert os.access(FILTER_SCRIPT, os.X_OK), f"Script is not executable: {FILTER_SCRIPT}"

    clean_files = glob.glob("/app/corpus/clean/*.json")
    assert clean_files, "No clean corpus files found"

    failed_files = []
    for fpath in clean_files:
        with open(fpath, "r") as f:
            expected_lines = [line.strip() for line in f if line.strip()]

        result = subprocess.run(["python3", FILTER_SCRIPT, fpath], capture_output=True, text=True)
        output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

        if len(output_lines) != len(expected_lines):
            failed_files.append(os.path.basename(fpath))
            continue

        assert result.returncode == 0, result.stderr
        assert [json.loads(line) for line in output_lines] == [json.loads(line) for line in expected_lines]

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {failed_files}"


def test_telemetry_sanitizer_evil_corpus():
    assert os.path.exists(FILTER_SCRIPT), f"Script missing at {FILTER_SCRIPT}"

    evil_files = glob.glob("/app/corpus/evil/*.json")
    assert evil_files, "No evil corpus files found"

    failed_files = []
    for fpath in evil_files:
        result = subprocess.run(["python3", FILTER_SCRIPT, fpath], capture_output=True, text=True)
        output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

        if len(output_lines) > 0:
            failed_files.append(os.path.basename(fpath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {failed_files}"


def test_telemetry_sanitizer_dynamic_mixed_input():
    seed = int.from_bytes(os.urandom(8), "big")
    rng = np.random.default_rng(seed)
    valid = [
        {
            "timestamp": float(rng.uniform(0.0, 10000.0)),
            "frame_id": int(rng.integers(0, 100000)),
            "bbox": [int(x) for x in rng.integers(0, 500, size=4)],
            "confidence": float(rng.uniform(0.0, 1.0)),
        },
        {"timestamp": 0.0, "frame_id": 0, "bbox": [0, 0, 0, 0], "confidence": 1.0},
    ]
    invalid = [
        {"timestamp": -0.01, "frame_id": 1, "bbox": [1, 2, 3, 4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": -1, "bbox": [1, 2, 3, 4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": 1, "bbox": [1, 2, 3], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": 1, "bbox": [1, 2, 3, -4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": 1, "bbox": [1, 2, "3", 4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": 1, "bbox": [1, 2, 3, 4], "confidence": 1.01},
        {"timestamp": "1.0", "frame_id": 1, "bbox": [1, 2, 3, 4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": True, "bbox": [1, 2, 3, 4], "confidence": 0.5},
        {"timestamp": 1.0, "frame_id": 1, "bbox": [1, 2, 3, 4]},
    ]

    fd, path = tempfile.mkstemp(prefix="telemetry_", suffix=".json")
    os.close(fd)
    try:
        with open(path, "w") as f:
            f.write("not json at all\n")
            for record in [valid[0], invalid[0], invalid[1], valid[1], *invalid[2:]]:
                f.write(json.dumps(record) + "\n")
        assert run_filter(path) == valid
    finally:
        os.unlink(path)


def decode_brightness(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not decode {video_path}"
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        values.append(float(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).mean()))
    cap.release()
    assert values, f"No frames decoded from {video_path}"
    return values


def read_and_validate_csv(expected_brightness):
    assert os.path.exists(CSV_PATH), f"CSV output missing at {CSV_PATH}"
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames == ["frame_id", "timestamp_sec", "brightness", "rolling_avg"], \
        f"Incorrect CSV columns: {reader.fieldnames}"
    assert len(rows) == len(expected_brightness), \
        f"Expected {len(expected_brightness)} rows, got {len(rows)}"

    for i, row in enumerate(rows):
        assert int(row["frame_id"]) == i, f"Expected frame_id {i}, got {row['frame_id']}"
        assert abs(float(row["timestamp_sec"]) - (i / 30.0)) < 0.1, \
            f"Incorrect timestamp for frame {i}"
        brightness = float(row["brightness"])
        assert np.isfinite(brightness), f"Non-finite brightness at frame {i}"
        assert abs(brightness - expected_brightness[i]) < 0.75, \
            f"Incorrect brightness at frame {i}: expected {expected_brightness[i]}, got {brightness}"

        start_idx = max(0, i - 4)
        expected_rolling = sum(float(rows[j]["brightness"]) for j in range(start_idx, i + 1)) / (i - start_idx + 1)
        assert abs(float(row["rolling_avg"]) - expected_rolling) < 0.1, \
            f"Incorrect rolling average at frame {i}: expected {expected_rolling}, got {row['rolling_avg']}"


def run_video_script(command=None):
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    if command is None:
        result = subprocess.run([VIDEO_SCRIPT], capture_output=True, text=True, timeout=120)
    else:
        result = subprocess.run(["/bin/bash", "-c", command], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"Video pipeline failed: {result.stderr}"
    assert os.path.exists(CSV_PATH), "Video pipeline did not create video_stats.csv"


def make_unpredictable_video(path):
    seed = int.from_bytes(os.urandom(8), "big")
    rng = np.random.default_rng(seed)
    frame_count = 18 + (seed % 9)
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 30.0, (96, 64))
    assert writer.isOpened(), "Could not create verifier video"
    for i in range(frame_count):
        gray = rng.integers(0, 256, size=(64, 96), dtype=np.uint8)
        gray[:, :8] = (i * 31 + seed) % 256
        frame = cv2.merge([gray, gray, gray])
        writer.write(frame)
    writer.release()
    return frame_count


def test_video_etl_pipeline_output():
    assert os.path.exists(VIDEO_SCRIPT), f"Script missing at {VIDEO_SCRIPT}"
    assert os.access(VIDEO_SCRIPT, os.X_OK), f"Script is not executable: {VIDEO_SCRIPT}"

    fd, backup = tempfile.mkstemp(prefix="traffic_backup_", suffix=".mp4")
    os.close(fd)
    shutil.copy2(VIDEO_PATH, backup)
    try:
        expected_original = decode_brightness(VIDEO_PATH)
        assert len(expected_original) == 150, f"Expected 150 source frames, got {len(expected_original)}"

        make_unpredictable_video(VIDEO_PATH)
        expected_dynamic = decode_brightness(VIDEO_PATH)
        run_video_script()
        read_and_validate_csv(expected_dynamic)
    finally:
        shutil.copy2(backup, VIDEO_PATH)
        os.unlink(backup)

    run_video_script()
    read_and_validate_csv(expected_original)


def test_cron_job_scheduled_and_command_executes_pipeline():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "No crontab found for the user"

    cron_lines = [line for line in result.stdout.splitlines() if not line.strip().startswith("#") and line.strip()]

    found = False
    command = None
    for line in cron_lines:
        if VIDEO_SCRIPT in line:
            parts = line.split()
            if len(parts) >= 5:
                if parts[0] == "0" and parts[1] == "*":
                    found = True
                    if len(parts) >= 6:
                        command = line.split(None, 5)[5]
                    break

    assert found, "Cron job for /home/user/process_video.py at the top of every hour (minute 0) not found"
    assert command, "Cron entry has no command to execute"

    expected = decode_brightness(VIDEO_PATH)
    run_video_script(command)
    read_and_validate_csv(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
