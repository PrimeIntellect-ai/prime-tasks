#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import matplotlib.image as mpimg
import numpy as np
from scipy.integrate import quad
from scipy.stats import gaussian_kde

SCRIPT = "/home/user/analysis.py"
FASTA = "/home/user/data/sequences.fasta"
RESULTS = "/home/user/results.txt"
PLOT = "/home/user/plot.png"

KD = {
    "A": 1.8, "R": -4.5, "N": -3.5, "D": -3.5, "C": 2.5,
    "Q": -3.5, "E": -3.5, "G": -0.4, "H": -3.2, "I": 4.5,
    "L": 3.8, "K": -3.9, "M": 1.9, "F": 2.8, "P": -1.6,
    "S": -0.8, "T": -0.7, "W": -0.9, "Y": -1.3, "V": 4.2,
}


def run_submission():
    assert os.path.isfile(SCRIPT), f"Required Python script is missing at {SCRIPT}"
    for path in (RESULTS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"analysis.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def read_result():
    assert os.path.isfile(RESULTS), f"Results file is missing at {RESULTS}"
    with open(RESULTS, "r") as f:
        content = f.read().strip()
    assert content, "Results file is empty."
    try:
        value = float(content)
    except ValueError:
        assert False, f"Results file does not contain a valid float. Found: {content}"
    assert math.isfinite(value), "Results file must contain a finite float."
    return value


def check_plot():
    assert os.path.isfile(PLOT), f"Plot file is missing at {PLOT}"
    with open(PLOT, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", "The file at /home/user/plot.png is not a valid PNG image."

    try:
        image = mpimg.imread(PLOT)
    except Exception as exc:
        assert False, f"plot.png is not a complete, decodable PNG: {exc}"
    assert image.ndim in (2, 3), "plot.png has an invalid image shape."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "plot.png is too small to be the requested plot."
    assert np.isfinite(image).all(), "plot.png contains invalid pixel values."
    assert float(np.ptp(image)) > 0.05, "plot.png is blank or effectively constant."


def oracle_integral(records):
    maxima = []
    standard = set(KD)
    for sequence in records:
        if any(aa not in standard for aa in sequence):
            continue
        values = np.asarray([KD[aa] for aa in sequence], dtype=float)
        if len(values) < 9:
            continue
        smooth = np.convolve(values, np.ones(9, dtype=float) / 9.0, mode="valid")
        if len(smooth) < 3:
            continue
        derivative = (smooth[2:] - smooth[:-2]) / 2.0
        maxima.append(float(np.max(np.abs(derivative))))

    assert len(maxima) >= 2 and np.ptp(maxima) > 0
    kde = gaussian_kde(np.asarray(maxima, dtype=float))
    return round(float(quad(lambda x: float(kde(x)[0]), 1.0, 5.0)[0]), 4)


def make_runtime_challenge():
    rng = secrets.SystemRandom()
    amino_acids = list(KD)
    pairs = [
        (a, b) for a in amino_acids for b in amino_acids
        if a < b and 3.2 <= abs(KD[a] - KD[b]) <= 9.0
    ]
    near_max = [pair for pair in pairs if abs(KD[pair[0]] - KD[pair[1]]) >= 8.0]
    lower = [pair for pair in pairs if abs(KD[pair[0]] - KD[pair[1]]) <= 5.0]
    middle = [pair for pair in pairs if 5.0 < abs(KD[pair[0]] - KD[pair[1]]) < 8.0]

    selected = [rng.choice(near_max), rng.choice(lower), rng.choice(middle)]
    remaining = [pair for pair in pairs if pair not in selected]
    selected.extend(rng.sample(remaining, 9))

    records = []
    for left, right in selected:
        if rng.randrange(2):
            left, right = right, left
        left_count = rng.randint(16, 28)
        right_count = rng.randint(16, 28)
        records.append(left * left_count + right * right_count)
    records.extend(["MKTII", "MKTIIXZ"])
    rng.shuffle(records)
    return records


def write_fasta(records):
    with open(FASTA, "w") as f:
        for index, sequence in enumerate(records, 1):
            f.write(f">runtime_{index}\n{sequence}\n")


def test_submission_executes_and_computes_outputs():
    # Execute against the provided dataset rather than trusting pre-created files.
    run_submission()
    value = read_result()
    expected_value = 0.1702
    assert math.isclose(value, expected_value, abs_tol=0.001), (
        f"Expected integral value close to {expected_value}, but got {value}"
    )
    check_plot()

    # Replace the input with a runtime-generated valid/invalid mixture and derive
    # the expected answer independently, preventing a fixed scalar from passing.
    records = make_runtime_challenge()
    expected = oracle_integral(records)
    write_fasta(records)
    run_submission()
    actual = read_result()
    assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=0.000051), (
        f"Runtime dataset integral should round to {expected:.4f}, but got {actual}"
    )
    check_plot()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
