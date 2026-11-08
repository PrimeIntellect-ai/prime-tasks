#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import secrets
import subprocess
import tempfile

import cv2

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.cpp"
CSV_PATH = "/home/user/frame_brightness.csv"
VIDEO_PATH = "/app/video/sensor_feed.mp4"


def run_detector(log_path, csv_path, strict=False):
    result = subprocess.run(
        [DETECTOR, log_path, csv_path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if strict:
        assert result.returncode == 0, f"Detector exited with {result.returncode}: {result.stderr}"
        assert result.stdout in ("CLEAN\n", "EVIL\n"), f"Invalid detector output: {result.stdout!r}"
    return result.stdout.strip()


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector executable not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector at {DETECTOR} is not executable"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, "C++ source is empty"


def test_csv_exists():
    assert os.path.isfile(CSV_PATH), f"CSV file not found at {CSV_PATH}"


def test_csv_matches_video_frames():
    with tempfile.TemporaryDirectory(prefix="verify_frames_") as frame_dir:
        pattern = os.path.join(frame_dir, "frame_%06d.png")
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", VIDEO_PATH, "-vf", "fps=1", pattern],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        frame_files = sorted(
            os.path.join(frame_dir, name)
            for name in os.listdir(frame_dir)
            if name.endswith(".png")
        )
        assert frame_files, "No frames could be extracted from the video at 1 fps"
        expected = []
        for path in frame_files:
            image = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
            assert image is not None, f"Could not read extracted frame {path}"
            expected.append(float(image.mean()))

    with open(CSV_PATH, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "Brightness CSV is empty"
    assert rows[0] == ["frame_id", "intensity"], "CSV header must be exactly frame_id,intensity"
    assert len(rows) == len(expected) + 1, "CSV must contain exactly one row per 1-fps video frame"

    for frame_id, (row, expected_intensity) in enumerate(zip(rows[1:], expected), start=1):
        assert len(row) == 2, f"Malformed CSV row for frame {frame_id}: {row!r}"
        assert row[0] == str(frame_id), f"Expected frame_id {frame_id}, got {row[0]!r}"
        try:
            actual = float(row[1])
        except ValueError:
            raise AssertionError(f"Invalid intensity for frame {frame_id}: {row[1]!r}")
        assert math.isfinite(actual), f"Non-finite intensity for frame {frame_id}"
        assert abs(actual - expected_intensity) <= 0.15, (
            f"Frame {frame_id} intensity {actual} does not match video-derived value {expected_intensity}"
        )


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isfile(DETECTOR), "Detector missing"
    assert os.path.isfile(CSV_PATH), "CSV missing"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".txt")]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".txt")]
    assert clean_files, "Clean corpus is empty"
    assert evil_files, "Evil corpus is empty"

    clean_modified = []
    evil_bypassed = []

    for f in clean_files:
        log_path = os.path.join(clean_dir, f)
        if run_detector(log_path, CSV_PATH) != "CLEAN":
            clean_modified.append(f)

    for f in evil_files:
        log_path = os.path.join(evil_dir, f)
        if run_detector(log_path, CSV_PATH) != "EVIL":
            evil_bypassed.append(f)

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected/misclassified): {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted/misclassified): {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def test_generated_path_independent_cases():
    rng = random.SystemRandom()
    frame_ids = rng.sample(range(10, 950), 10)
    brightness = {frame_id: float(4 * rng.randint(1, 63)) for frame_id in frame_ids}

    cases = []

    def add(line, expected):
        cases.append((line + "\n", expected))

    for frame_id in frame_ids:
        expected_temp = 0.75 * brightness[frame_id]
        delta = rng.uniform(-24.0, 24.0)
        voltage = rng.uniform(0.0, 24.0)
        add(f"FRAME_{frame_id:03d} TEMP_{expected_temp + delta:.6f} VOLT_{voltage:.6f} STAT_OK", "CLEAN")

    boundary_id = frame_ids[0]
    boundary_temp = 0.75 * brightness[boundary_id]
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp + 25.0:.6f} VOLT_0.0 STAT_OK", "CLEAN")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp - 25.0:.6f} VOLT_24.0 STAT_OK", "CLEAN")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp + 25.25:.6f} VOLT_12.0 STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp - 25.25:.6f} VOLT_12.0 STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp:.6f} VOLT_-0.001 STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp:.6f} VOLT_24.001 STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_NA VOLT_12.0 STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp:.6f} VOLT_NA STAT_OK", "EVIL")
    add(f"FRAME_{boundary_id:03d} TEMP_{boundary_temp:.6f} VOLT_12.0 STAT_NA", "EVIL")

    missing_id = next(i for i in range(1, 1000) if i not in brightness)
    add(f"FRAME_{missing_id:03d} TEMP_50.0 VOLT_12.0 STAT_OK", "EVIL")

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"verify_{secrets.token_hex(8)}_") as work:
        generated_csv = os.path.join(work, secrets.token_hex(8) + ".csv")
        with open(generated_csv, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["frame_id", "intensity"])
            for frame_id, intensity in brightness.items():
                writer.writerow([frame_id, f"{intensity:.6f}"])

        failures = []
        for line, expected in cases:
            log_path = os.path.join(work, secrets.token_hex(12) + ".txt")
            with open(log_path, "w") as f:
                f.write(line)
            actual = run_detector(log_path, generated_csv, strict=True)
            if actual != expected:
                failures.append(f"input {line.strip()!r}: expected {expected}, got {actual}")

        assert not failures, "Generated-case failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
