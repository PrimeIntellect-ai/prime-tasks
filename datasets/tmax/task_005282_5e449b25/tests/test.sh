#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import stat

import cv2
import pytest

SIGNAL_PATH = "/home/user/signal.csv"
AGENT_PATH = "/home/user/evaluate_ll.py"
ORACLE_PATH = "/app/oracle_evaluate_ll"
VIDEO_PATH = "/app/experiment.mp4"


def extract_expected_signal():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    values = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            height, width = frame.shape[:2]
            assert height >= 100 and width >= 100, "Video frames are smaller than 100x100"
            y0 = (height - 100) // 2
            x0 = (width - 100) // 2
            red_mean = float(frame[y0:y0 + 100, x0:x0 + 100, 2].mean())
            values.append(red_mean / 255.0)
    finally:
        cap.release()
    assert values, "The experiment video contains no decodable frames"
    return values


def read_and_validate_signal():
    assert os.path.isfile(SIGNAL_PATH), "The file /home/user/signal.csv is missing. Did you extract the video signal?"
    assert not os.path.islink(SIGNAL_PATH), "signal.csv must be a regular file, not a symbolic link"
    assert stat.S_ISREG(os.stat(SIGNAL_PATH).st_mode), "signal.csv must be a regular file"

    with open(SIGNAL_PATH, "r", encoding="utf-8") as f:
        raw = f.read().strip()
    assert raw, "signal.csv is empty"

    pieces = raw.split(",")
    assert all(piece.strip() for piece in pieces), "signal.csv must be a comma-separated list of floats"
    try:
        actual = [float(piece) for piece in pieces]
    except ValueError as exc:
        pytest.fail(f"signal.csv contains a non-float value: {exc}")

    expected = extract_expected_signal()
    assert len(actual) == len(expected), (
        f"signal.csv has {len(actual)} samples, but the video has {len(expected)} frames"
    )
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isfinite(got), f"signal.csv sample {i} is not finite"
        assert abs(got - want) <= 1e-9, (
            f"signal.csv sample {i} is incorrect: got {got}, expected {want}"
        )
    return actual


def rk4_a_values(k1, k2, steps):
    dt = 0.1
    A = 1.0
    B = 0.0
    result = [A]
    for _ in range(steps):
        dA1 = -k1 * A
        dB1 = k1 * A - k2 * B

        A2 = A + 0.5 * dt * dA1
        B2 = B + 0.5 * dt * dB1
        dA2 = -k1 * A2
        dB2 = k1 * A2 - k2 * B2

        A3 = A + 0.5 * dt * dA2
        B3 = B + 0.5 * dt * dB2
        dA3 = -k1 * A3
        dB3 = k1 * A3 - k2 * B3

        A4 = A + dt * dA3
        B4 = B + dt * dB3
        dA4 = -k1 * A4
        dB4 = k1 * A4 - k2 * B4

        A += (dt / 6.0) * (dA1 + 2.0 * dA2 + 2.0 * dA3 + dA4)
        B += (dt / 6.0) * (dB1 + 2.0 * dB2 + 2.0 * dB3 + dB4)
        result.append(A)
    return result


def expected_ll(k1, k2, experimental):
    simulated = rk4_a_values(k1, k2, len(experimental) - 1)
    return -0.5 * sum(
        (sim - exp) ** 2 / 0.0025
        for sim, exp in zip(simulated, experimental)
    )


def run_float(command, description):
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"{description} failed. Stderr: {exc.stderr}")
    except Exception as exc:
        pytest.fail(f"{description} could not be run: {exc}")

    try:
        value = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"{description} output is not a single parseable float: {result.stdout!r}")
    assert math.isfinite(value), f"{description} returned a non-finite value: {value}"
    return value


def test_signal_csv_exists_and_matches_video():
    read_and_validate_signal()


def test_evaluate_ll_script_exists():
    assert os.path.isfile(AGENT_PATH), "The script /home/user/evaluate_ll.py is missing."
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} missing."
    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "evaluate_ll.py must not be a byte-identical copy of the reference implementation"


def test_fuzz_equivalence():
    experimental = read_and_validate_signal()
    with open(SIGNAL_PATH, "rb") as f:
        original_signal = f.read()

    random.seed(42)
    for _ in range(100):
        k1 = random.uniform(0.01, 2.0)
        k2 = random.uniform(0.01, 2.0)
        k1_str = f"{k1:.6f}"
        k2_str = f"{k2:.6f}"
        tested_k1 = float(k1_str)
        tested_k2 = float(k2_str)
        want = expected_ll(tested_k1, tested_k2, experimental)
        assert math.isfinite(want)

        oracle_val = run_float(
            [ORACLE_PATH, k1_str, k2_str],
            f"Oracle on k1={k1_str}, k2={k2_str}",
        )
        agent_val = run_float(
            ["python3", AGENT_PATH, k1_str, k2_str],
            f"Agent script on k1={k1_str}, k2={k2_str}",
        )

        assert abs(oracle_val - want) <= 1e-5, (
            f"Oracle disagreed with independently derived result for k1={k1_str}, k2={k2_str}"
        )
        assert abs(agent_val - oracle_val) <= 1e-5, (
            f"Mismatch on inputs k1={k1_str}, k2={k2_str}.\n"
            f"Expected output: {want}\n"
            f"Oracle output:   {oracle_val}\n"
            f"Agent output:    {agent_val}"
        )
        assert abs(agent_val - want) <= 1e-5, (
            f"Agent output disagrees with independently derived result on k1={k1_str}, k2={k2_str}"
        )

    with open(SIGNAL_PATH, "rb") as f:
        assert f.read() == original_signal, "evaluate_ll.py modified signal.csv while being evaluated"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
