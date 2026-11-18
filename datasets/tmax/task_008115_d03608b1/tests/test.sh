#!/bin/bash
mkdir -p /logs/verifier

TMPDIR=$(mktemp -d)
DATA=/home/user/spectroscopy_data.h5
REPORT=/home/user/test_report.txt
SOURCE=/home/user/regression_test.cpp
BINARY="$TMPDIR/regression_test"
cp "$DATA" "$TMPDIR/original_data.h5"
if [ -f "$REPORT" ]; then
    cp "$REPORT" "$TMPDIR/preexisting_report.txt"
fi

cleanup() {
    cp "$TMPDIR/original_data.h5" "$DATA" 2>/dev/null || true
    if [ -f "$TMPDIR/original_report.txt" ]; then
        cp "$TMPDIR/original_report.txt" "$REPORT" 2>/dev/null || true
    elif [ -f "$TMPDIR/preexisting_report.txt" ]; then
        cp "$TMPDIR/preexisting_report.txt" "$REPORT" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

run_checks() {
    [ -f "$SOURCE" ] || { echo "Missing C++ source: $SOURCE"; return 1; }
    [ ! -L "$SOURCE" ] || { echo "C++ source must not be a symlink"; return 1; }
    [ -s "$SOURCE" ] || { echo "C++ source is empty"; return 1; }

    timeout 45s h5c++ -std=c++17 -O2 "$SOURCE" -lfftw3 -o "$BINARY" || {
        echo "Failed to compile regression_test.cpp"
        return 1
    }
    [ -x "$BINARY" ] || { echo "Compilation did not produce an executable"; return 1; }

    nm -D "$BINARY" 2>/dev/null | grep -Eq 'fftw_plan_' || {
        echo "Executable does not reference an FFTW planning function"
        return 1
    }
    nm -D "$BINARY" 2>/dev/null | grep -Eq 'fftw_execute' || {
        echo "Executable does not reference an FFTW execution function"
        return 1
    }

    rm -f "$REPORT"
    timeout 20s "$BINARY" || { echo "Program failed on the supplied input"; return 1; }

    cat > "$TMPDIR/test_final_state.py" <<'PYTEST'
import os

def test_test_report_exists():
    """Check that the generated test report exists."""
    report_file = "/home/user/test_report.txt"
    assert os.path.exists(report_file), f"Output report file is missing: {report_file}"
    assert os.path.isfile(report_file), f"Path is not a file: {report_file}"

def test_test_report_contents():
    """Check the contents of the test report for the correct format and values."""
    report_file = "/home/user/test_report.txt"
    assert os.path.exists(report_file), f"Output report file is missing: {report_file}"

    expected_output = (
        "Calculated Peak Frequency: 125.00 Hz\n"
        "Baseline Peak Frequency: 125.00 Hz\n"
        "Regression Test: PASS"
    )

    with open(report_file, "r") as f:
        content = f.read().strip()

    assert expected_output in content, (
        f"The contents of {report_file} do not match the expected output.\n"
        f"Expected:\n{expected_output}\n"
        f"Got:\n{content}"
    )
PYTEST
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$TMPDIR/test_final_state.py" -x --tb=short || return 1
    cp "$REPORT" "$TMPDIR/original_report.txt"

    python3 - "$BINARY" <<'PY'
import os
import subprocess
import sys

import h5py
import numpy as np

binary = sys.argv[1]
data_path = "/home/user/spectroscopy_data.h5"
report_path = "/home/user/test_report.txt"
N = 1000
Fs = 1000.0
window = 0.5 * (1.0 - np.cos(2.0 * np.pi * np.arange(N) / (N - 1)))

def write_input(signal, baseline):
    with h5py.File(data_path, "w") as f:
        f.create_dataset("signal", data=np.asarray(signal, dtype=np.float64))
        f.create_dataset("baseline_peak", data=np.asarray(baseline, dtype=np.float64))

def run_and_check(signal, baseline, expected_bin, expected_result):
    write_input(signal, baseline)
    try:
        os.remove(report_path)
    except FileNotFoundError:
        pass
    completed = subprocess.run([binary], timeout=20, capture_output=True, text=True)
    assert completed.returncode == 0, (
        f"Program exited with {completed.returncode}\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(report_path), "Program did not create test_report.txt"
    expected = (
        f"Calculated Peak Frequency: {expected_bin * Fs / N:.2f} Hz\n"
        f"Baseline Peak Frequency: {baseline:.2f} Hz\n"
        f"Regression Test: {expected_result}"
    )
    with open(report_path, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected dynamic report:\n{expected}\nGot:\n{actual}"

# Find a deterministic broadband input whose Hann-windowed peak differs from
# its unwindowed peak. This makes omission of the required window observable.
rng = np.random.default_rng(20260912)
signal = None
hann_bin = None
for _ in range(5000):
    candidate = rng.normal(0.0, 1.0, N)
    hann_power = np.abs(np.fft.rfft(candidate * window))[:N // 2] ** 2
    rect_power = np.abs(np.fft.rfft(candidate))[:N // 2] ** 2
    hb = int(np.argmax(hann_power))
    rb = int(np.argmax(rect_power))
    second = float(np.partition(hann_power, -2)[-2])
    if 5 <= hb < N // 2 - 5 and hb != rb and hann_power[hb] > 1.15 * second:
        signal = candidate
        hann_bin = hb
        break
assert signal is not None, "Could not construct the Hann-window test input"
run_and_check(signal, float(hann_bin), hann_bin, "PASS")

# Use a new signal and a deliberately mismatched baseline to verify that the
# signal and scalar HDF5 datasets are both read and that FAIL is calculated.
t = np.arange(N) / Fs
signal = np.sin(2 * np.pi * 211.0 * t) + 0.2 * np.sin(2 * np.pi * 90.0 * t + 0.3)
run_and_check(signal, 212.0, 211, "FAIL")
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
