#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile

import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
FEATURES_PATH = "/home/user/features.csv"
RESULT_PATH = "/home/user/bootstrap_result.txt"
EXPECTED_COLUMNS = ["frame_index", "luma_avg", "delta_luma"]


def extract_expected_luma(video_path):
    fd, metadata_path = tempfile.mkstemp(prefix="signalstats_", suffix=".txt")
    os.close(fd)
    try:
        proc = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-i", video_path,
                "-vf", f"signalstats,metadata=print:file={metadata_path}",
                "-f", "null", "-",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"Independent ffmpeg extraction failed: {proc.stderr}"

        values = []
        with open(metadata_path, "r") as f:
            for line in f:
                if line.startswith("lavfi.signalstats.YAVG="):
                    values.append(float(line.split("=", 1)[1].strip()))
        assert values, f"No frame YAVG values were derived from {video_path}"
        return values
    finally:
        if os.path.exists(metadata_path):
            os.unlink(metadata_path)


def validate_outputs(video_path):
    expected_luma = extract_expected_luma(video_path)
    expected_delta = [0.0] + [
        expected_luma[i] - expected_luma[i - 1]
        for i in range(1, len(expected_luma))
    ]

    assert os.path.exists(FEATURES_PATH), f"Features CSV missing at {FEATURES_PATH}"
    with open(FEATURES_PATH, "r") as f:
        assert f.readline().rstrip("\r\n") == "frame_index,luma_avg,delta_luma", "CSV header is not exact"

    try:
        df = pd.read_csv(FEATURES_PATH)
    except Exception as e:
        pytest.fail(f"Failed to read {FEATURES_PATH} as CSV: {e}")

    assert list(df.columns) == EXPECTED_COLUMNS, (
        f"CSV columns do not match expected schema. Got {list(df.columns)}, expected {EXPECTED_COLUMNS}"
    )
    assert len(df) == len(expected_luma), (
        f"Expected one CSV row for each of {len(expected_luma)} video frames, got {len(df)}"
    )

    try:
        frame_indices = pd.to_numeric(df["frame_index"], errors="raise").tolist()
        actual_luma = pd.to_numeric(df["luma_avg"], errors="raise").tolist()
        actual_delta = pd.to_numeric(df["delta_luma"], errors="raise").tolist()
    except Exception as e:
        pytest.fail(f"CSV contains non-numeric feature data: {e}")

    assert frame_indices == list(range(len(expected_luma))), (
        "frame_index must be consecutive integers starting at 0"
    )
    assert all(math.isfinite(float(v)) for v in actual_luma + actual_delta), "CSV contains non-finite values"

    for i, (actual, expected) in enumerate(zip(actual_luma, expected_luma)):
        assert abs(float(actual) - expected) <= 1e-4, (
            f"Frame {i} luma_avg is {actual}, but ffmpeg-derived YAVG is {expected}"
        )
    for i, (actual, expected) in enumerate(zip(actual_delta, expected_delta)):
        assert abs(float(actual) - expected) <= 1e-3, (
            f"Frame {i} delta_luma is {actual}, expected {expected}"
        )

    assert os.path.exists(RESULT_PATH), f"Bootstrap result missing at {RESULT_PATH}"
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    try:
        agent_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse bootstrap result as float. Got: '{content}'")
    assert math.isfinite(agent_val), "Bootstrap result must be a finite floating-point number"

    valid_delta = [
        expected_delta[i] for i, luma in enumerate(expected_luma) if luma >= 50.0
    ]
    assert valid_delta, "No valid frames found with luma_avg >= 50.0"
    expected_mean = sum(valid_delta) / len(valid_delta)
    error = abs(agent_val - expected_mean)
    threshold = 0.5
    assert error <= threshold, (
        f"Bootstrap result metric threshold exceeded. Expected sample mean {expected_mean:.4f}, "
        f"agent bootstrap grand mean {agent_val:.4f}, error {error:.4f} > {threshold}"
    )


def run_pipeline(video_path):
    for path in (FEATURES_PATH, RESULT_PATH):
        if os.path.lexists(path):
            os.unlink(path)
    try:
        proc = subprocess.run(
            [SCRIPT_PATH, video_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            cwd="/home/user",
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Pipeline timed out while processing {video_path}")
    assert proc.returncode == 0, (
        f"Pipeline failed for {video_path} with exit code {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    validate_outputs(video_path)


def test_pipeline_executes_and_derives_video_features():
    # First exercise the reusable input argument on a verifier-generated video so
    # hard-coded or self-reported values cannot pass.
    magnitude = 0.08 + secrets.randbelow(9) / 100.0
    brightness = magnitude if secrets.randbelow(2) else -magnitude
    challenge_path = "/tmp/verifier_challenge.mp4"
    make_video = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", "/app/experiment.mp4",
            "-vf", f"eq=brightness={brightness}", "-an",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", challenge_path,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert make_video.returncode == 0, f"Failed to create challenge video: {make_video.stderr}"
    run_pipeline(challenge_path)

    # Run the required artifact last and leave its required outputs in place.
    run_pipeline("/app/experiment.mp4")


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist"
    assert os.path.isfile(script_path), f"{script_path} is not a file"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"


def test_features_csv_schema():
    features_path = "/home/user/features.csv"
    assert os.path.exists(features_path), f"Features CSV missing at {features_path}"
    try:
        df = pd.read_csv(features_path)
    except Exception as e:
        pytest.fail(f"Failed to read {features_path} as CSV: {e}")
    expected_columns = ["frame_index", "luma_avg", "delta_luma"]
    assert list(df.columns) == expected_columns, f"CSV columns do not match expected schema. Got {list(df.columns)}, expected {expected_columns}"


def test_bootstrap_result_metric():
    features_path = "/home/user/features.csv"
    result_path = "/home/user/bootstrap_result.txt"
    assert os.path.exists(features_path), f"Features CSV missing at {features_path}"
    assert os.path.exists(result_path), f"Bootstrap result missing at {result_path}"
    try:
        df = pd.read_csv(features_path)
    except Exception as e:
        pytest.fail(f"Failed to read {features_path} as CSV: {e}")
    if "luma_avg" not in df.columns or "delta_luma" not in df.columns:
        pytest.fail("CSV is missing 'luma_avg' or 'delta_luma' columns required for evaluation.")
    valid_df = df[df["luma_avg"] >= 50.0]
    assert not valid_df.empty, "No valid frames found with luma_avg >= 50.0. Check feature extraction logic."
    expected_mean = valid_df["delta_luma"].mean()
    with open(result_path, "r") as f:
        content = f.read().strip()
    try:
        agent_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse bootstrap result as float. Got: '{content}'")
    assert math.isfinite(agent_val), "Bootstrap result must be finite"
    error = abs(agent_val - expected_mean)
    threshold = 0.5
    assert error <= threshold, (
        f"Bootstrap result metric threshold exceeded.\n"
        f"Expected (true sample mean of filtered data): {expected_mean:.4f}\n"
        f"Agent bootstrap grand mean: {agent_val:.4f}\n"
        f"Absolute error: {error:.4f} > Threshold: {threshold}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
