#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import subprocess

import numpy as np
import pandas as pd
from scipy.optimize import curve_fit

SCRIPT_PATH = "/home/user/analyze.py"
SIGNAL_PATH = "/home/user/signal.csv"
OUTPUT_PATH = "/home/user/output.txt"


def run_analyzer():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    assert os.path.isfile(OUTPUT_PATH), "analyze.py did not create /home/user/output.txt"


def parse_strict_output():
    with open(OUTPUT_PATH, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 4, f"Expected exactly 4 lines, found {len(lines)}."

    labels = ["Frequency", "Amplitude", "Phase", "Offset"]
    values = []
    for line, label in zip(lines, labels):
        prefix = label + ": "
        assert line.startswith(prefix), f"Expected line beginning with '{prefix}', got '{line}'."
        text = line[len(prefix):]
        assert text and text.count(".") == 1, f"{label} must be written with exactly 2 decimal places."
        whole, fraction = text.lstrip("-").split(".")
        assert whole.isdigit() and len(fraction) == 2 and fraction.isdigit(), \
            f"{label} must be written with exactly 2 decimal places."
        values.append(float(text))
    return lines, values


def expected_for(t, y):
    dt = float(t[1] - t[0])
    frequencies = np.fft.rfftfreq(len(t), d=dt)
    magnitudes = np.abs(np.fft.rfft(y))
    magnitudes[0] = 0.0
    f_dom = float(frequencies[np.argmax(magnitudes)])

    def model(x, amplitude, phase, offset):
        return amplitude * np.sin(2 * np.pi * f_dom * x + phase) + offset

    initial = [(float(np.max(y)) - float(np.min(y))) / 2.0, 0.0, float(np.mean(y))]
    params, _ = curve_fit(model, t, y, p0=initial, maxfev=20000)
    amplitude, phase, offset = map(float, params)
    if amplitude < 0:
        amplitude = -amplitude
        phase += np.pi
    phase = (phase + np.pi) % (2 * np.pi) - np.pi

    return [
        f"Frequency: {f_dom:.2f}",
        f"Amplitude: {amplitude:.2f}",
        f"Phase: {phase:.2f}",
        f"Offset: {offset:.2f}",
    ]


def test_analyze_script_exists_and_runs():
    """Test that analyze.py exists, is valid Python, and generates output when run."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    py_compile.compile(SCRIPT_PATH, doraise=True)
    run_analyzer()


def test_output_file_content():
    """Retain the original expected-output assertions on the supplied signal."""
    assert os.path.exists(OUTPUT_PATH), f"The output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected_lines = [
        "Frequency: 2.50",
        "Amplitude: 4.19",
        "Phase: 0.51",
        "Offset: 2.01"
    ]

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines in {OUTPUT_PATH}, found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch on line {i+1} of {OUTPUT_PATH}. Expected '{expected}', got '{actual}'."


def test_analyzer_processes_new_signals():
    """Exercise the submitted script on signals whose answers are derived at test time."""
    with open(SIGNAL_PATH, "rb") as f:
        original_signal = f.read()

    probes = [
        (1.70, 3.10, -1.20, -0.40, 101),
        (3.80, 1.85, 2.20, 5.30, 202),
    ]

    try:
        for frequency, amplitude, phase, offset, seed in probes:
            rng = np.random.default_rng(seed)
            t = np.linspace(0.0, 10.0, 1000, endpoint=False)
            y = amplitude * np.sin(2 * np.pi * frequency * t + phase) + offset
            y = y + rng.normal(0.0, 0.12, size=t.size)
            expected = expected_for(t, y)
            pd.DataFrame({"t": t, "y": y}).to_csv(SIGNAL_PATH, index=False)

            run_analyzer()
            actual, values = parse_strict_output()
            assert actual == expected, f"For a generated signal, expected {expected}, got {actual}."
            assert values[1] > 0, "Amplitude must be positive."
            assert -np.pi <= values[2] <= np.pi, "Phase must be within [-pi, pi]."
    finally:
        with open(SIGNAL_PATH, "wb") as f:
            f.write(original_signal)
        try:
            run_analyzer()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
