#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import time

import cv2
import numpy as np
import pytest

EXTRACTOR = "/home/user/extract_math.py"
PIPELINE = "/home/user/ci_pipeline.sh"
PROJECT = "/home/user/sim_engine"
CONSTANTS = "/home/user/sim_engine/src/trajectory_constants.rs"
VIDEO = "/app/experiment.mp4"


def parse_constants(path):
    with open(path, "r") as f:
        content = f.read()

    a_match = re.search(r'COEFF_A:\s*f64\s*=\s*([-+\d\.eE]+);', content)
    b_match = re.search(r'COEFF_B:\s*f64\s*=\s*([-+\d\.eE]+);', content)
    c_match = re.search(r'COEFF_C:\s*f64\s*=\s*([-+\d\.eE]+);', content)
    assert a_match, "Could not find COEFF_A in trajectory_constants.rs"
    assert b_match, "Could not find COEFF_B in trajectory_constants.rs"
    assert c_match, "Could not find COEFF_C in trajectory_constants.rs"
    return np.array([float(a_match.group(1)), float(b_match.group(1)), float(c_match.group(1))])


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    if os.path.exists(CONSTANTS):
        os.unlink(CONSTANTS)
    shutil.rmtree(os.path.join(PROJECT, "target"), ignore_errors=True)

    started = time.time()
    result = subprocess.run(
        ["bash", "-x", PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    trace = result.stdout + "\n" + result.stderr
    assert result.returncode == 0, f"Pipeline failed:\n{trace}"
    assert re.search(r'extract_math\.py(?:\s|$)', trace), "Pipeline did not invoke extract_math.py"
    assert re.search(r'cargo\s+build(?:\s|$)', trace), "Pipeline did not execute cargo build"
    assert re.search(r'cargo\s+test(?:\s|$)', trace), "Pipeline did not execute cargo test"
    assert os.path.isfile(CONSTANTS), "Pipeline did not generate trajectory_constants.rs"
    assert os.path.getmtime(CONSTANTS) >= started - 1, "Generated constants file is stale"
    binary = os.path.join(PROJECT, "target", "debug", "sim_engine")
    assert os.path.isfile(binary), "Pipeline did not build the Rust binary"


def test_extract_math_script_exists():
    script_path = "/home/user/extract_math.py"
    assert os.path.exists(script_path), f"Expected script missing at {script_path}"
    assert os.path.isfile(script_path), f"Path {script_path} is not a file"


def test_ci_pipeline_script_exists():
    script_path = "/home/user/ci_pipeline.sh"
    assert os.path.exists(script_path), f"Expected script missing at {script_path}"
    assert os.path.isfile(script_path), f"Path {script_path} is not a file"


def test_trajectory_constants_accuracy():
    constants_path = "/home/user/sim_engine/src/trajectory_constants.rs"
    assert os.path.exists(constants_path), f"Generated file missing at {constants_path}"

    with open(constants_path, 'r') as f:
        content = f.read()

    a_match = re.search(r'COEFF_A:\s*f64\s*=\s*([-\d\.e]+);', content)
    b_match = re.search(r'COEFF_B:\s*f64\s*=\s*([-\d\.e]+);', content)
    c_match = re.search(r'COEFF_C:\s*f64\s*=\s*([-\d\.e]+);', content)

    assert a_match, "Could not find COEFF_A in trajectory_constants.rs"
    assert b_match, "Could not find COEFF_B in trajectory_constants.rs"
    assert c_match, "Could not find COEFF_C in trajectory_constants.rs"

    A_pred = float(a_match.group(1))
    B_pred = float(b_match.group(1))
    C_pred = float(c_match.group(1))

    A_true, B_true, C_true = 0.002, -1.2, 200.0

    err_a = abs((A_pred - A_true) / A_true)
    err_b = abs((B_pred - B_true) / B_true)
    err_c = abs((C_pred - C_true) / C_true)

    max_err = max(err_a, err_b, err_c)
    threshold = 0.05

    assert max_err <= threshold, (
        f"Maximum relative error {max_err:.4f} exceeds threshold {threshold}. "
        f"Predictions: A={A_pred}, B={B_pred}, C={C_pred}. "
        f"Expected: A={A_true}, B={B_true}, C={C_true}."
    )


def test_extractor_processes_video_numerically():
    original_video = VIDEO + ".verifier_backup"
    constants_backup = None
    shutil.copyfile(VIDEO, original_video)
    if os.path.exists(CONSTANTS):
        with open(CONSTANTS, "rb") as f:
            constants_backup = f.read()

    try:
        if secrets.randbits(1):
            a = 0.00135 + secrets.randbelow(301) / 1_000_000.0
        else:
            a = 0.00245 + secrets.randbelow(301) / 1_000_000.0
        vertex_x = 230 + secrets.randbelow(121)

        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(VIDEO, fourcc, 30.0, (640, 480))
        assert writer.isOpened(), "Could not create verifier video"
        for x in range(60, 581, 13):
            frame = np.full((480, 640, 3), 255, dtype=np.uint8)
            y = int(a * ((x - vertex_x) ** 2) + 40.0)
            cv2.circle(frame, (x, y), 5, (0, 0, 0), -1)
            writer.write(frame)
        writer.release()

        # Independently derive the expected fit from the actual encoded video.
        cap = cv2.VideoCapture(VIDEO)
        points = []
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            ys, xs = np.nonzero(gray < 100)
            if len(xs):
                points.append((float(xs.mean()), float(ys.mean())))
        cap.release()
        assert len(points) >= 30, "Verifier video did not contain enough detectable frames"
        expected = np.polyfit(
            np.array([p[0] for p in points]),
            np.array([p[1] for p in points]),
            2,
        )

        result = subprocess.run(
            ["python3", EXTRACTOR],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, (
            "extract_math.py failed on a valid trajectory video:\n"
            + result.stdout + "\n" + result.stderr
        )
        assert os.path.isfile(CONSTANTS), "Extractor did not generate trajectory_constants.rs"
        predicted = parse_constants(CONSTANTS)
        tolerances = np.maximum(np.abs(expected) * 0.05, np.array([3e-5, 0.02, 1.0]))
        assert np.all(np.abs(predicted - expected) <= tolerances), (
            f"Extractor did not fit the supplied video. Predicted {predicted.tolist()}, "
            f"independently fitted {expected.tolist()}"
        )
    finally:
        shutil.move(original_video, VIDEO)
        if constants_backup is not None:
            with open(CONSTANTS, "wb") as f:
                f.write(constants_backup)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
