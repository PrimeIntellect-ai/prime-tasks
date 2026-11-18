#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path

import pytest

EXECUTABLE = "/home/user/analyze_spectra"
SOURCE = "/home/user/analyze_spectra.cpp"
RESULT = "/home/user/result.txt"
DATA = "/home/user/data.csv"
REFERENCE = "/home/user/reference.txt"


def run_program(executable, data_path, ref_path):
    completed = subprocess.run(
        [executable, data_path, ref_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), f"Result file {RESULT} was not created."


def expected_energy(freqs, psds):
    total = 0.0
    for i in range(len(freqs) - 1):
        total += 0.5 * (freqs[i + 1] - freqs[i]) * (psds[i] + psds[i + 1])
    return total


def assert_result(expected, reference):
    with open(RESULT, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]

    assert len(actual_lines) == 2, (
        f"Expected exactly 2 lines in {RESULT}, but got {len(actual_lines)}."
    )
    expected_line1 = f"Total Energy: {expected:.2f}"
    expected_line2 = f"Exceeds Reference: {'Yes' if expected > reference else 'No'}"
    assert actual_lines[0] == expected_line1, (
        f"First line mismatch. Expected: '{expected_line1}', Got: '{actual_lines[0]}'"
    )
    assert actual_lines[1] == expected_line2, (
        f"Second line mismatch. Expected: '{expected_line2}', Got: '{actual_lines[1]}'"
    )


def make_cases():
    rng = random.SystemRandom()
    cases = []
    for case_index in range(4):
        count = rng.randint(4, 9)
        freqs = [0.0]
        for _ in range(count - 1):
            freqs.append(freqs[-1] + rng.randint(1, 5))
        psds = [float(rng.randint(0, 30)) for _ in range(count)]
        energy = expected_energy(freqs, psds)
        if case_index % 3 == 0:
            reference = energy - 0.25
        elif case_index % 3 == 1:
            reference = energy + 0.25
        else:
            reference = energy
        cases.append((freqs, psds, energy, reference))
    return cases


def test_executable_exists():
    executable_path = EXECUTABLE
    assert os.path.isfile(executable_path), f"Executable {executable_path} was not found. Did you compile the C++ program?"
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled executable."


def test_result_file_contents():
    result_path = RESULT
    data_path = DATA
    ref_path = REFERENCE

    assert os.path.isfile(data_path), f"Data file {data_path} is missing."
    assert os.path.isfile(ref_path), f"Reference file {ref_path} is missing."

    # Execute the submitted artifact rather than trusting a pre-created result file.
    run_program(EXECUTABLE, data_path, ref_path)
    assert os.path.isfile(result_path), f"Result file {result_path} was not created."

    # Compute expected values dynamically.
    with open(data_path, 'r') as f:
        lines = f.read().strip().split('\n')

    freqs = []
    psds = []
    for line in lines[1:]:
        if not line.strip():
            continue
        f_val, p_val = line.split(',')
        freqs.append(float(f_val))
        psds.append(float(p_val))

    expected = expected_energy(freqs, psds)
    with open(ref_path, 'r') as f:
        ref_energy = float(f.read().strip())

    assert_result(expected, ref_energy)


def test_source_compute_function_and_executables(tmp_path):
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

    obj = tmp_path / "submission.o"
    harness_cpp = tmp_path / "harness.cpp"
    harness = tmp_path / "harness"
    rebuilt = tmp_path / "analyze_spectra_rebuilt"

    harness_cpp.write_text(r'''#include <iostream>
#include <iomanip>
#include <vector>
using namespace std;
double computeTotalEnergy(const vector<double>&, const vector<double>&);
int main() {
    size_t n;
    if (!(cin >> n)) return 1;
    vector<double> freq(n), psd(n);
    for (double &v : freq) cin >> v;
    for (double &v : psd) cin >> v;
    cout << setprecision(17) << computeTotalEnergy(freq, psd) << "\n";
    return 0;
}
''')

    subprocess.run(
        ["g++", "-std=c++17", "-Dmain=analyze_spectra_submission_main", "-c", SOURCE, "-o", str(obj)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20,
    )
    subprocess.run(
        ["g++", "-std=c++17", str(harness_cpp), str(obj), "-o", str(harness)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20,
    )
    subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", str(rebuilt)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20,
    )

    cases = make_cases()

    # Call computeTotalEnergy directly so the required function itself must implement integration.
    for freqs, psds, expected, _ in cases:
        input_text = (
            f"{len(freqs)}\n"
            + " ".join(map(str, freqs)) + "\n"
            + " ".join(map(str, psds)) + "\n"
        )
        completed = subprocess.run(
            [str(harness)], input=input_text, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10,
        )
        assert completed.returncode == 0, completed.stderr
        actual = float(completed.stdout.strip())
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12)

    # Exercise both the requested executable and a fresh build from the submitted source.
    for executable in (EXECUTABLE, str(rebuilt)):
        for index, (freqs, psds, expected, reference) in enumerate(cases):
            csv_path = tmp_path / f"case_{index}.csv"
            ref_path = tmp_path / f"case_{index}.txt"
            rows = ["freq,psd"] + [f"{f},{p}" for f, p in zip(freqs, psds)]
            csv_path.write_text("\n".join(rows) + "\n")
            ref_path.write_text(f"{reference}\n")
            if os.path.exists(RESULT):
                os.remove(RESULT)
            run_program(executable, str(csv_path), str(ref_path))
            assert_result(expected, reference)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
