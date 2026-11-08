#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re

import numpy as np

RESULT_PATH = "/home/user/result.txt"
REFERENCES_PATH = "/home/user/references.csv"


def test_result_file_exists():
    assert os.path.isfile(RESULT_PATH), (
        f"File {RESULT_PATH} is missing. Did you write the output to the correct location?"
    )


def test_result_file_contents():
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} is missing."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    match = re.fullmatch(r"([^,\r\n]+), ([0-9]+\.[0-9]{2})", content)
    assert match, (
        f"Contents of {RESULT_PATH} must be formatted exactly as "
        f"'MaterialName, 18.XX', but got {content!r}."
    )

    material = match.group(1)
    submitted_frequency = float(match.group(2))

    # Derive the expected center using the specified sampling, FFT, and
    # three-bin quadratic interpolation. Averaged zero-mean white noise adds
    # a flat expected power floor, so it does not move this expected vertex.
    t = np.linspace(0.0, 10.0, 1000, endpoint=False)
    signal = 3.0 * np.sin(2.0 * np.pi * 18.23 * t)
    frequencies = np.fft.rfftfreq(t.size, d=0.01)
    power = np.abs(np.fft.rfft(signal)) ** 2
    peak_index = int(np.argmax(power))
    assert 0 < peak_index < len(power) - 1
    a, b, _ = np.polyfit(
        frequencies[peak_index - 1:peak_index + 2],
        power[peak_index - 1:peak_index + 2],
        2,
    )
    expected_vertex = -b / (2.0 * a)

    # Permit Monte Carlo variation while requiring the reported, two-decimal
    # estimate to remain near the result of the instructed interpolation.
    assert abs(submitted_frequency - expected_vertex) <= 0.0300001, (
        f"Reported frequency {submitted_frequency:.2f} is not consistent with "
        f"the specified spectral interpolation (expected near {expected_vertex:.4f} Hz)."
    )

    with open(REFERENCES_PATH, newline="") as f:
        references = [
            (row["Material"], float(row["Frequency"]))
            for row in csv.DictReader(f)
        ]
    expected_material = min(
        references, key=lambda item: abs(item[1] - submitted_frequency)
    )[0]
    assert material == expected_material, (
        f"Material {material!r} is incorrect for the reported frequency; "
        f"the closest reference is {expected_material!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
