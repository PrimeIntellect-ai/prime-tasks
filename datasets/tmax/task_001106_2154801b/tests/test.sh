#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import numpy as np

SOURCE = "/home/user/analyze.go"
SIGNAL = "/home/user/signal.csv"
RESULT = "/home/user/result.json"

RESULT_PATTERN = re.compile(
    r'^\{\s*"f_peak"\s*:\s*(\d+)\s*,\s*"A"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{2})\s*,\s*"phi"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{2})\s*\}$'
)


def read_signal(path):
    values = np.genfromtxt(path, delimiter=",", names=True)
    return np.asarray(values["t"], dtype=float), np.asarray(values["y"], dtype=float)


def independently_fit(path):
    t, y = read_signal(path)
    best = None
    for frequency in range(1, 21):
        angle = 2.0 * math.pi * frequency * t
        design = np.column_stack((np.cos(angle), np.sin(angle)))
        coefficients, _, _, _ = np.linalg.lstsq(design, y, rcond=None)
        prediction = design @ coefficients
        mse = float(np.mean((prediction - y) ** 2))
        if best is None or mse < best[0]:
            cosine_coefficient = float(coefficients[0])
            sine_coefficient = float(coefficients[1])
            amplitude = math.hypot(cosine_coefficient, sine_coefficient)
            phase = math.atan2(-sine_coefficient, cosine_coefficient)
            best = (mse, frequency, amplitude, phase)
    return best[1], round(best[2], 2), round(best[3], 2)


def run_program():
    if os.path.lexists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        ["go", "run", SOURCE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"go run failed with exit code {completed.returncode}:\n{completed.stderr}"
    )
    assert os.path.exists(RESULT), f"File {RESULT} is missing."
    assert os.path.isfile(RESULT), f"Path {RESULT} is not a file."


def load_and_validate_result(expected):
    with open(RESULT, "r", encoding="utf-8") as handle:
        raw = handle.read().strip()

    match = RESULT_PATTERN.fullmatch(raw)
    assert match, (
        "result.json must contain exactly f_peak, A, and phi in that order, "
        "with A and phi written with exactly two decimal places."
    )

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as error:
        assert False, f"Failed to parse JSON in {RESULT}: {error}"

    assert set(data) == {"f_peak", "A", "phi"}, "result.json has missing or extra keys."
    assert type(data["f_peak"]) is int, f"Expected 'f_peak' to be an integer, got {type(data['f_peak'])}."
    assert type(data["A"]) in (int, float), f"Expected 'A' to be a number, got {type(data['A'])}."
    assert type(data["phi"]) in (int, float), f"Expected 'phi' to be a number, got {type(data['phi'])}."

    expected_f, expected_a, expected_phi = expected
    assert data["f_peak"] == expected_f, f"Expected f_peak={expected_f}, got {data['f_peak']}."
    assert math.isclose(float(data["A"]), expected_a, abs_tol=0.005), f"Expected A={expected_a:.2f}, got {data['A']}."
    assert math.isclose(float(data["phi"]), expected_phi, abs_tol=0.005), f"Expected phi={expected_phi:.2f}, got {data['phi']}."
    return data


def test_go_analysis_and_result():
    assert os.path.exists(SOURCE), f"File {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"Path {SOURCE} is not a file."
    with open(SOURCE, "r", encoding="utf-8") as handle:
        source_text = handle.read()
    assert re.search(r"(?m)^\s*package\s+main\b", source_text), "analyze.go is not a Go main package."
    assert re.search(r"\bfunc\s+main\s*\(", source_text), "analyze.go has no main function."

    with open(SIGNAL, "rb") as handle:
        original_signal = handle.read()

    try:
        # Exercise the submitted Go program on a second valid signal so a
        # hard-coded result for the shipped CSV cannot pass.
        with open(SIGNAL, "w", encoding="utf-8") as handle:
            handle.write("t,y\n")
            for i in range(100):
                t = i / 100.0
                y = 1.75 * math.cos(2.0 * math.pi * 13 * t - 1.10)
                y += 0.03 * math.cos(2.0 * math.pi * 3 * t + 0.25)
                handle.write(f"{t:.4f},{y:.8f}\n")
        synthetic_expected = independently_fit(SIGNAL)
        run_program()
        load_and_validate_result(synthetic_expected)
    finally:
        with open(SIGNAL, "wb") as handle:
            handle.write(original_signal)

    # Run again on the actual experimental data and retain the original checks.
    original_expected = independently_fit(SIGNAL)
    run_program()
    data = load_and_validate_result(original_expected)

    f_peak = data["f_peak"]
    amplitude = data["A"]
    phase = data["phi"]
    assert f_peak == 7, f"Expected 'f_peak' to be 7, got {f_peak}."
    assert 3.10 <= amplitude <= 3.35, f"Expected 'A' to be between 3.10 and 3.35, got {amplitude}."
    assert 0.65 <= phase <= 0.90, f"Expected 'phi' to be between 0.65 and 0.90, got {phase}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
