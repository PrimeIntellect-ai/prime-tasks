#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import odeint

SCRIPT_PATH = "/home/user/sanitize.sh"
REFERENCE_PATH = "/tmp/reference_solution.csv"


def count_red_frames():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json",
         "/app/calibration.mp4"],
        check=True, capture_output=True, text=True
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/calibration.mp4",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        check=True, capture_output=True
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0, "Could not decode calibration video"
    frames = np.frombuffer(decoded, dtype=np.uint8).reshape(-1, height, width, 3)
    red = (
        (frames[..., 0] >= 240).all(axis=(1, 2))
        & (frames[..., 1] <= 20).all(axis=(1, 2))
        & (frames[..., 2] <= 20).all(axis=(1, 2))
    )
    return int(red.sum())


def assert_reference_is_calibrated():
    assert os.path.isfile(REFERENCE_PATH), "The reference solution was not generated at /tmp/reference_solution.csv"
    C = count_red_frames()
    assert C == 42, f"Calibration video should contain 42 red frames, decoded {C}"

    actual = pd.read_csv(REFERENCE_PATH)
    assert list(actual.columns) == ["time", "value"], "Reference must have exactly the columns time,value"
    assert len(actual) == 100, "Reference must contain exactly 100 rows"
    assert np.isfinite(actual[["time", "value"]].to_numpy(dtype=float)).all(), "Reference contains non-finite values"

    t = np.linspace(0, 10, 100)
    expected_y = odeint(lambda y, current_t: -C * y, 1.0, t).reshape(-1)
    np.testing.assert_allclose(actual["time"].to_numpy(dtype=float), t, rtol=0, atol=1e-12)
    np.testing.assert_allclose(
        actual["value"].to_numpy(dtype=float), expected_y,
        rtol=1e-10, atol=1e-12,
        err_msg="Reference trajectory was not generated with the video-derived C"
    )
    return actual


def test_sanitize_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "The sanitize.sh script was not found at /home/user/sanitize.sh"


def test_reference_solution_exists():
    assert os.path.isfile(REFERENCE_PATH), "The reference solution was not generated at /tmp/reference_solution.csv"


def test_reference_solution_is_calibrated():
    assert_reference_is_calibrated()


def test_adversarial_corpus_filtering():
    script_path = SCRIPT_PATH
    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus), "Clean corpus missing"
    assert os.path.isdir(evil_corpus), "Evil corpus missing"

    clean_files = set(f for f in os.listdir(clean_corpus) if f.endswith(".csv"))
    evil_files = set(f for f in os.listdir(evil_corpus) if f.endswith(".csv"))

    with tempfile.TemporaryDirectory() as clean_out_dir, tempfile.TemporaryDirectory() as evil_out_dir:
        result_clean = subprocess.run(
            ["bash", script_path, clean_corpus, clean_out_dir],
            capture_output=True, text=True
        )
        assert result_clean.returncode == 0, f"Script failed on clean corpus:\n{result_clean.stderr}"

        result_evil = subprocess.run(
            ["bash", script_path, evil_corpus, evil_out_dir],
            capture_output=True, text=True
        )
        assert result_evil.returncode == 0, f"Script failed on evil corpus:\n{result_evil.stderr}"

        clean_out_files = set(f for f in os.listdir(clean_out_dir) if f.endswith(".csv"))
        missing_clean = clean_files - clean_out_files
        evil_out_files = set(f for f in os.listdir(evil_out_dir) if f.endswith(".csv"))
        bypassed_evil = evil_out_files

        error_msgs = []
        if missing_clean:
            error_msgs.append(f"{len(missing_clean)} of {len(clean_files)} clean modified/rejected. Examples: {list(missing_clean)[:3]}")
        if bypassed_evil:
            error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed. Examples: {list(bypassed_evil)[:3]}")
        if error_msgs:
            pytest.fail(" | ".join(error_msgs))


def test_randomized_mixed_corpus_and_exact_copies():
    reference = assert_reference_is_calibrated()
    reference_bytes = Path(REFERENCE_PATH).read_bytes()
    t = reference["time"].to_numpy(dtype=float)
    y = reference["value"].to_numpy(dtype=float)
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "big"))

    with tempfile.TemporaryDirectory(prefix="input_") as input_dir, tempfile.TemporaryDirectory(prefix="output_") as output_dir:
        expected = {}
        cases = []

        for _ in range(5):
            values = y + rng.uniform(-0.42, 0.42, size=100)
            cases.append((values, True))

        for magnitude in (0.5001, 0.63, 0.8, 1.1, 2.0):
            values = y + rng.uniform(-0.2, 0.2, size=100)
            index = int(rng.integers(0, 100))
            values[index] = y[index] + magnitude * (-1 if rng.integers(0, 2) else 1)
            cases.append((values, False))

        rng.shuffle(cases)
        for values, accepted in cases:
            name = f"{secrets.token_hex(12)}.csv"
            path = Path(input_dir) / name
            pd.DataFrame({"time": t, "value": values}).to_csv(path, index=False)
            if accepted:
                expected[name] = path.read_bytes()

        result = subprocess.run(
            ["bash", SCRIPT_PATH, input_dir, output_dir],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"Script failed on randomized mixed corpus:\n{result.stderr}"

        produced = {p.name for p in Path(output_dir).iterdir() if p.is_file() and p.suffix == ".csv"}
        assert produced == set(expected), f"Incorrect randomized filtering: expected {set(expected)}, got {produced}"
        for name, original_bytes in expected.items():
            assert (Path(output_dir) / name).read_bytes() == original_bytes, f"{name} was not copied unchanged"

        assert Path(REFERENCE_PATH).read_bytes() == reference_bytes, "sanitize.sh modified the reference solution"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
