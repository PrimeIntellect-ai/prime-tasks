#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import numpy as np

HOME = "/home/user"
SCRIPT = f"{HOME}/run_analysis.sh"
RAW = f"{HOME}/raw_sensor.dat"
REFERENCE = f"{HOME}/reference.txt"
CLEAN = f"{HOME}/clean_data.csv"
NOISY = f"{HOME}/noisy_data.csv"
REPORT = f"{HOME}/analysis_report.txt"
TOOL = f"{HOME}/get_freq.py"

EXPECTED_TOOL = '''import sys
import numpy as np

try:
    data = np.genfromtxt(sys.argv[1], delimiter=',', skip_header=1)
    t = data[:, 0]
    v = data[:, 1]

    n = len(v)
    dt = t[1] - t[0]
    freqs = np.fft.fftfreq(n, d=dt)
    fft_vals = np.abs(np.fft.fft(v))

    # ignore DC component
    fft_vals[0] = 0

    idx = np.argmax(fft_vals)
    dom_freq = abs(freqs[idx])

    print(f"{dom_freq:.2f}")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
'''


def canonical_inputs():
    t = np.arange(0, 2.0, 0.01)
    v = 2.0 * np.sin(2 * np.pi * 5.0 * t) + 0.5 * np.sin(2 * np.pi * 15.0 * t)
    raw = " ".join(f"{time:.2f}_{val:.4f}" for time, val in zip(t, v)) + "\n"
    return raw, "5.00\n"


def parse_raw(raw_text):
    rows = []
    for token in raw_text.split():
        parts = token.split("_")
        assert len(parts) == 2, f"Malformed raw token: {token}"
        rows.append((parts[0], parts[1], float(parts[0]), float(parts[1])))
    return rows


def read_csv(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, f"File {path} is empty"
    assert lines[0] == "time,value", f"Incorrect header in {path}"

    rows = []
    for index, line in enumerate(lines[1:], start=1):
        parts = line.split(",")
        assert len(parts) == 2, f"Incorrect format in row {index} of {path}: {line}"
        try:
            rows.append((parts[0], parts[1], float(parts[0]), float(parts[1])))
        except ValueError:
            raise AssertionError(f"Non-numeric data in row {index} of {path}: {line}")
    return lines, rows


def dominant_frequency(rows):
    t = np.array([row[2] for row in rows], dtype=float)
    v = np.array([row[3] for row in rows], dtype=float)
    assert len(rows) >= 2
    freqs = np.fft.fftfreq(len(v), d=t[1] - t[0])
    amplitudes = np.abs(np.fft.fft(v))
    amplitudes[0] = 0
    return f"{abs(freqs[np.argmax(amplitudes)]):.2f}"


def validate_outputs(raw_text, reference_text):
    raw_rows = parse_raw(raw_text)
    clean_lines, clean_rows = read_csv(CLEAN)

    assert len(clean_lines) == len(raw_rows) + 1, \
        f"Expected {len(raw_rows)} data points + header, found {len(clean_lines)}"
    assert len(clean_rows) == len(raw_rows)
    for index, (source, clean) in enumerate(zip(raw_rows, clean_rows), start=1):
        assert clean[2] == source[2], f"Incorrect time in clean row {index}"
        assert clean[3] == source[3], f"Incorrect value in clean row {index}"

    noisy_lines, noisy_rows = read_csv(NOISY)
    assert len(noisy_lines) == len(clean_lines), \
        "Line count mismatch between clean and noisy data"
    assert len(noisy_rows) == len(clean_rows)
    for index, (clean, noisy) in enumerate(zip(clean_rows, noisy_rows), start=1):
        assert noisy[0] == clean[0], f"Time column modified in noisy row {index}"
        assert abs(noisy[3] - (clean[3] + 0.05)) < 1e-5, \
            f"Expected +0.05 in noisy row {index}, got {noisy[3]} vs {clean[3]}"

    clean_freq = dominant_frequency(clean_rows)
    noisy_freq = dominant_frequency(noisy_rows)
    reference = float(reference_text.strip())
    comparison = "MATCH" if abs(float(clean_freq) - reference) < 0.5 else "MISMATCH"
    stable = "YES" if noisy_freq == clean_freq else "NO"
    expected = [
        f"DATA_POINTS: {len(clean_rows)}",
        f"CLEAN_FREQ: {clean_freq}",
        f"REF_COMPARISON: {comparison}",
        f"NOISY_FREQ: {noisy_freq}",
        f"STABLE: {stable}",
    ]

    assert os.path.isfile(REPORT), f"Missing file: {REPORT}"
    with open(REPORT) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Incorrect report. Expected {expected}, got {actual}"


def execute_and_validate(raw_text, reference_text):
    with open(RAW, "w") as f:
        f.write(raw_text)
    with open(REFERENCE, "w") as f:
        f.write(reference_text)
    for path in (CLEAN, NOISY, REPORT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f"run_analysis.sh failed ({result.returncode}):\n{result.stdout}\n{result.stderr}"
    with open(RAW) as f:
        assert f.read() == raw_text, "run_analysis.sh modified raw_sensor.dat"
    with open(REFERENCE) as f:
        assert f.read() == reference_text, "run_analysis.sh modified reference.txt"
    validate_outputs(raw_text, reference_text)


def test_complete_pipeline():
    assert os.path.isfile(SCRIPT), f"Missing script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"

    assert os.path.isfile(TOOL), f"Missing provided tool: {TOOL}"
    with open(TOOL) as f:
        assert f.read() == EXPECTED_TOOL, "Provided get_freq.py was modified"

    original_raw, original_reference = canonical_inputs()
    with open(RAW) as f:
        assert f.read() == original_raw, "Provided raw_sensor.dat was modified"
    with open(REFERENCE) as f:
        assert f.read() == original_reference, "Provided reference.txt was modified"

    # Exercise the script on an unpredictable second dataset so fixed CSV/report
    # artifacts cannot satisfy the verifier.
    n = secrets.choice((128, 160, 192))
    dt = 0.01
    k = secrets.randbelow(10) + 6
    t = np.arange(n) * dt
    primary = k / (n * dt)
    secondary = (k + 3) / (n * dt)
    v = 1.7 * np.sin(2 * np.pi * primary * t) + 0.31 * np.cos(2 * np.pi * secondary * t)
    dynamic_raw = " ".join(
        f"{time:.6f}_{value:.6f}" for time, value in zip(t, v)
    ) + "\n"
    # This deliberately exercises the MISMATCH branch.
    dynamic_reference = f"{primary + 1.25:.6f}\n"
    execute_and_validate(dynamic_raw, dynamic_reference)

    # Restore and verify the required final artifacts for the provided dataset.
    execute_and_validate(original_raw, original_reference)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
