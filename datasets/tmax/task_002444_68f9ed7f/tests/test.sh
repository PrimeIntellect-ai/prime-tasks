#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import uuid

import pytest


def test_task1_frame_avg():
    """
    Validates that the student extracted the frame at exactly 00:00:02,
    converted it to grayscale, and calculated the correct mean pixel intensity.
    """
    student_file = "/home/user/frame_avg.txt"
    assert os.path.exists(student_file), f"Student file {student_file} does not exist."

    truth_frame = "/tmp/truth_frame.png"
    try:
        subprocess.run([
            "ffmpeg", "-y", "-ss", "00:00:02", "-i", "/app/training_source.mp4",
            "-vframes", "1", "-pix_fmt", "gray", truth_frame
        ], capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to extract truth frame using ffmpeg: {e.stderr.decode()}")

    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        pytest.fail("numpy or PIL not available to compute truth.")

    truth_val = np.mean(np.array(Image.open(truth_frame)))
    truth_str = f"{truth_val:.2f}"

    with open(student_file, "r") as f:
        student_val = f.read().strip()

    assert student_val == truth_str, f"Mean pixel intensity mismatch. Expected {truth_str}, got {student_val}"


def test_task2_filter_corpus():
    """
    Validates that the student's script correctly accepts clean files (exit code 0)
    and rejects evil files (exit code 1).
    """
    script_path = "/home/user/filter_corpus.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        res = subprocess.run([script_path, cf], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        res = subprocess.run([script_path, ef], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_failed)}")

    assert not errors, " | ".join(errors)


def _expected_status(csv_text):
    for line in csv_text.splitlines():
        for field in line.split(','):
            value = float(field.strip())
            if not math.isfinite(value) or abs(value) > 65504:
                return 1
    return 0


def test_task2_generated_arbitrary_csvs():
    """Exercise the executable on unpredictable paths, dimensions, and values."""
    script_path = "/home/user/filter_corpus.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist or is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix=f"csv-{uuid.uuid4().hex}-")

    safe_specials = [
        "65504", "-65504", "+65504.0", "-0.0", "6.5504e4",
        "-6.5504E+4", "0.0000000001", "-3.1415926535"
    ]
    poison_values = [
        "65505", "-65505", "65504.5", "-70000.25", "1e100",
        "inf", "-inf", "+INF", "NaN", "nan"
    ]

    def random_safe():
        style = rng.randrange(4)
        if style == 0:
            return str(rng.randint(-65504, 65504))
        if style == 1:
            return f"{rng.randint(-6000000, 6000000) / 100:.2f}"
        if style == 2:
            return f"{rng.randint(-60000, 60000):.6e}"
        return rng.choice(safe_specials)

    contents = [
        "65504,-65504,0\n1e-20,-1e-20,42\n",
        "65505\n",
        "-65505,0\n",
        "1,2,3\n4,NaN,6\n",
        "1,-inf\n",
        "6.5504e4,-6.5504e4\n",
        "1e100,2\n",
    ]

    for _ in range(28):
        rows = rng.randint(1, 9)
        cols = rng.randint(1, 11)
        matrix = [[random_safe() for _ in range(cols)] for _ in range(rows)]
        if rng.choice([True, False]):
            matrix[rng.randrange(rows)][rng.randrange(cols)] = rng.choice(poison_values)
        contents.append("\n".join(",".join(row) for row in matrix) + "\n")

    cases = []
    for content in contents:
        path = os.path.join(workdir, f"{uuid.uuid4().hex}.csv")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        cases.append((path, _expected_status(content)))

    rng.shuffle(cases)
    failures = []
    for path, expected in cases:
        result = subprocess.run([script_path, path], capture_output=True)
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)} expected exit {expected}, got {result.returncode}"
            )

    assert not failures, "Generated CSV failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
