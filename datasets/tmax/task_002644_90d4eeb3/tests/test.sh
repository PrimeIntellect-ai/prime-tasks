#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import sys

import numpy as np
from scipy.integrate import solve_ivp

SCRIPT_PATH = "/home/user/duffing_mc.py"
OUTPUT_PATH = "/home/user/dominant_freq.txt"


def test_script_exists():
    """Check that the Python script was created."""
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/duffing_mc.py does not exist."


def test_script_runs_and_generates_output():
    """Execute the submitted artifact and require it to create a fresh output."""
    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        assert False, "The script did not finish within 300 seconds."

    assert result.returncode == 0, (
        "The script failed when executed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        "The script did not generate /home/user/dominant_freq.txt."
    )


def reference_dominant_frequency():
    """Independently perform the specified deterministic Monte Carlo simulation."""
    np.random.seed(42)
    t_eval = np.linspace(0.0, 50.0, 1000)
    spectra = []

    for _ in range(100):
        amplitude = np.random.normal(2.0, 0.5)

        def duffing(t, state):
            x, v = state
            return [v, -0.1 * v - x - x**3 + amplitude * np.cos(1.2 * t)]

        solution = solve_ivp(
            duffing,
            (0.0, 50.0),
            [0.0, 0.0],
            method="RK45",
            t_eval=t_eval,
        )
        assert solution.success, "Reference Duffing integration failed."
        spectra.append(np.abs(np.fft.fft(solution.y[0])) ** 2)

    average_power = np.mean(spectra, axis=0)
    frequencies = np.fft.fftfreq(1000, d=t_eval[1] - t_eval[0])
    positive = frequencies > 0
    dominant = frequencies[positive][np.argmax(average_power[positive])]
    return round(float(dominant), 3)


def test_output_file_exists_and_valid():
    """Check that the output is formatted correctly and matches the simulation."""
    output_path = "/home/user/dominant_freq.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content != "", "The output file is empty."

    try:
        val = float(content)
    except ValueError:
        assert False, f"The content of {output_path} is not a valid float: '{content}'"

    # Check if it has 3 decimal places (if there is a decimal point)
    if '.' in content:
        decimals = content.split('.')[1]
        assert len(decimals) == 3, f"Expected 3 decimal places, found {len(decimals)} in '{content}'"
    else:
        # If it's an integer like "1", it should be "1.000"
        assert False, f"Expected 3 decimal places, but no decimal point found in '{content}'"

    # The driving frequency is 1.2 rad/s -> ~0.191 Hz.
    # The dominant frequency should be somewhere around this range.
    assert 0.0 < val < 1.0, f"The dominant frequency {val} is outside the expected physical range (0.0, 1.0) Hz."

    expected = reference_dominant_frequency()
    assert val == expected, (
        f"Expected dominant frequency {expected:.3f} from the specified simulation, "
        f"but found {content}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
