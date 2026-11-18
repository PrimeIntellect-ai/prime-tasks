#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import imageio.v2 as imageio
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/evaluate_sample.py"
CLEAN_CORPUS_DIR = "/app/eval_corpus/clean/"
EVIL_CORPUS_DIR = "/app/eval_corpus/evil/"
VIDEO_PATH = "/app/calibration.mp4"
DB_PATH = "/app/telemetry.db"


def run_sample(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=30,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for f in clean_files:
        result = run_sample(f)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted): {failed_files}"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing at {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for f in evil_files:
        result = run_sample(f)
        if result.returncode == 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed/accepted (should be rejected): {failed_files}"


def test_randomized_samples_and_replacement_calibration_video():
    # Use neutral randomized paths and fresh DB records, and replace the calibration
    # video with another valid strobe so neither path labels nor a hardcoded 3 Hz
    # answer can satisfy this test.
    token = secrets.token_hex(12)
    workdir = tempfile.mkdtemp(prefix="telemetry_" + token + "_")
    backup_video = os.path.join(workdir, "original_video.mp4")
    shutil.copy2(VIDEO_PATH, backup_video)

    fps = 30
    duration = 10
    frequency = random.choice([2, 5, 6])
    period = fps // frequency
    sample_specs = []
    conn = None

    try:
        frames = []
        for frame_no in range(fps * duration):
            value = 255 if frame_no % period == 0 else 0
            frames.append(np.full((64, 64, 3), value, dtype=np.uint8))
        imageio.mimwrite(VIDEO_PATH, frames, fps=fps)

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        slopes = [frequency, frequency, frequency, frequency + 1.25,
                  frequency - 1.4, -float(frequency), frequency + 0.35]
        random.shuffle(slopes)

        for slope in slopes:
            sample_id = "sample_" + secrets.token_hex(10)
            csv_path = os.path.join(workdir, sample_id + ".csv")
            intercept = random.uniform(-4.0, 4.0)
            with open(csv_path, "w") as csv_file:
                csv_file.write("timestamp,signal_1\n")
                for t in range(80):
                    signal_1 = random.uniform(-10.0, 10.0)
                    signal_2 = slope * signal_1 + intercept
                    csv_file.write(f"{float(t)},{signal_1}\n")
                    cursor.execute(
                        "INSERT INTO sensor_data(timestamp, sample_id, signal_2) VALUES (?, ?, ?)",
                        (float(t), sample_id, signal_2),
                    )
            sample_specs.append((csv_path, sample_id, abs(slope - frequency) <= 0.1))
        conn.commit()

        random.shuffle(sample_specs)
        failures = []
        for csv_path, sample_id, should_accept in sample_specs:
            result = run_sample(csv_path)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append((sample_id, should_accept, result.returncode))

        assert not failures, f"Randomized content-based classifications were incorrect: {failures}"
    finally:
        if conn is not None:
            try:
                conn.executemany(
                    "DELETE FROM sensor_data WHERE sample_id = ?",
                    [(sample_id,) for _, sample_id, _ in sample_specs],
                )
                conn.commit()
            finally:
                conn.close()
        shutil.copy2(backup_video, VIDEO_PATH)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
