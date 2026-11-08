#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import cv2
import pytest


def test_first_10_frames_csv():
    csv_path = "/home/user/first_10_frames.csv"
    assert os.path.exists(csv_path), f"Missing output file: {csv_path}"

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"CSV file {csv_path} is empty")

        assert header == ['frame_id', 'intensity', 'event_flag'], f"Incorrect header in {csv_path}: {header}"

        rows = list(reader)
        assert len(rows) == 10, f"Expected exactly 10 data rows, found {len(rows)}"

        for i, row in enumerate(rows):
            assert len(row) == 3, f"Row {i} has {len(row)} columns instead of 3"
            assert row[0] == str(i), f"Row {i}: Expected frame_id '{i}', got '{row[0]}'"
            try:
                intensity = float(row[1])
            except ValueError:
                pytest.fail(f"Row {i}: Intensity '{row[1]}' is not a valid float")

            assert 0.0 <= intensity <= 255.0, f"Row {i}: Intensity {intensity} is out of bounds [0.0, 255.0]"

            if '.' in row[1]:
                decimals = len(row[1].split('.')[1])
                assert decimals <= 2 or round(intensity, 2) == intensity, f"Row {i}: Intensity '{row[1]}' not rounded to 2 decimal places"

            assert row[2] == "False", f"Row {i}: Expected event_flag 'False', got '{row[2]}'"


def test_frame_intensities_are_derived_from_video():
    video_path = "/app/experiment_record.mp4"
    csv_path = "/home/user/first_10_frames.csv"
    assert os.path.isfile(video_path), f"Missing video: {video_path}"
    assert os.path.isfile(csv_path), f"Missing output file: {csv_path}"

    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not decode {video_path}"
    expected = []
    try:
        for frame_id in range(10):
            ok, frame = cap.read()
            assert ok and frame is not None, f"Could not decode frame {frame_id}"
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            expected.append(round(float(gray.mean()), 2))
    finally:
        cap.release()

    with open(csv_path, 'r', newline='') as f:
        rows = list(csv.DictReader(f))

    assert len(rows) == 10
    for i, (row, expected_intensity) in enumerate(zip(rows, expected)):
        actual = float(row['intensity'])
        assert actual == pytest.approx(expected_intensity, abs=0.01), (
            f"Frame {i}: expected grayscale average {expected_intensity:.2f}, got {actual}"
        )


def test_validator_clean_corpus():
    script_path = "/home/user/validate_csv.py"
    assert os.path.exists(script_path), f"Missing validator script: {script_path}"

    clean_dir = "/app/clean_corpus/"
    assert os.path.exists(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No CSV files found in clean corpus"

    failed_files = []
    for cf in clean_files:
        res = subprocess.run(['python3', script_path, cf], capture_output=True)
        if res.returncode != 0:
            failed_files.append(os.path.basename(cf))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files rejected: {failed_files}"


def test_validator_evil_corpus():
    script_path = "/home/user/validate_csv.py"
    assert os.path.exists(script_path), f"Missing validator script: {script_path}"

    evil_dir = "/app/evil_corpus/"
    assert os.path.exists(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No CSV files found in evil corpus"

    bypassed_files = []
    for ef in evil_files:
        res = subprocess.run(['python3', script_path, ef], capture_output=True)
        if res.returncode == 0:
            bypassed_files.append(os.path.basename(ef))

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed validation: {bypassed_files}"


def test_validator_on_generated_unpredictable_inputs():
    script_path = "/home/user/validate_csv.py"
    assert os.path.isfile(script_path), f"Validator is not a regular file: {script_path}"

    header = "frame_id,intensity,event_flag\n"
    rng = random.SystemRandom()
    cases = []

    for _ in range(6):
        frame_a = secrets.randbelow(1_000_000)
        frame_b = secrets.randbelow(1_000_000)
        intensity_a = secrets.randbelow(25500) / 100.0
        intensity_b = secrets.randbelow(25500) / 100.0
        flag_a = rng.choice(["True", "False"])
        flag_b = rng.choice(["True", "False"])
        valid = (
            header
            + f"{frame_a},{intensity_a:.2f},{flag_a}\n"
            + f"{frame_b},{intensity_b:.2f},{flag_b}\n"
        )
        cases.append((valid, 0))

        cases.extend([
            (header + f"-{frame_a + 1},{intensity_a:.2f},{flag_a}\n", 1),
            (header + f"{frame_a},255.{secrets.randbelow(899) + 101},{flag_a}\n", 1),
            (header + f"{frame_a},-{secrets.randbelow(999) + 1}.{secrets.randbelow(99):02d},{flag_a}\n", 1),
            (header + f"{frame_a},{intensity_a:.2f},{rng.choice(['TRUE', 'FALSE', 'true', 'false'])}\n", 1),
            (header + f"{frame_a}.0,{intensity_a:.2f},{flag_a}\n", 1),
            (header + f"{frame_a},not-a-number,{flag_a}\n", 1),
            (header + f"{frame_a},{intensity_a:.2f},{flag_a},extra\n", 1),
        ])

    cases.extend([
        (header + "0,0.0,False\n1,255.0,True\n", 0),
        (header, 1),
        ("", 1),
        ("intensity,frame_id,event_flag\n0,1.0,False\n", 1),
        ("frame_id,intensity,event_flags\n0,1.0,False\n", 1),
        ("frame_id,intensity,event_flag,extra\n0,1.0,False,x\n", 1),
        ("0,1.0,False\n", 1),
        (header + ",1.0,False\n", 1),
        (header + "0,,False\n", 1),
        (header + "0,1.0,\n", 1),
        (header + "0,1.0\n", 1),
        (header + "0,1.0,False\n\n", 1),
        (header + "0,1.0,False\n   \n", 1),
        (header + "NaN,1.0,False\n", 1),
        (header + "0,NaN,False\n", 1),
        (header + "0,inf,False\n", 1),
        (header + "0,-inf,False\n", 1),
    ])

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="csv_validation_") as temp_dir:
        failures = []
        for content, expected_code in cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex + ".csv")
            with open(path, "w", newline="") as f:
                f.write(content)

            result = subprocess.run(
                ['python3', script_path, path],
                capture_output=True,
                timeout=5,
            )
            if result.returncode != expected_code:
                failures.append((content, expected_code, result.returncode))

        assert not failures, f"Validator returned incorrect exit codes for generated cases: {failures[:3]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
