#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess

SOURCE_PATH = '/home/user/analyze.cpp'
OUTPUT_PATH = '/home/user/analysis_output.txt'
CSV_PATH = '/home/user/energy_signal.csv'
BINARY_PATH = '/tmp/analyze_submission'


def read_csv(path):
    xs = []
    ys = []
    with open(path, 'r') as f:
        next(f)
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            xs.append(float(parts[0]))
            ys.append(float(parts[1]))
    return xs, ys


def expected_lines(path):
    xs, ys = read_csv(path)

    integral = 0.0
    for i in range(1, len(xs)):
        dx = xs[i] - xs[i - 1]
        integral += (ys[i - 1] + ys[i]) / 2.0 * dx

    analytical = 10.0 * math.sin(10.0)
    error = abs(integral - analytical)

    max_d = 0.0
    for i in range(1, len(xs) - 1):
        dx2 = xs[i + 1] - xs[i - 1]
        d = abs(ys[i + 1] - ys[i - 1]) / dx2
        if d > max_d:
            max_d = d

    return [
        f"Numerical Integral: {integral:.4f}",
        f"Analytical Integral: {analytical:.4f}",
        f"Integral Error: {error:.4f}",
        f"Max Derivative: {max_d:.4f}",
    ]


def assert_output(expected):
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"
    with open(OUTPUT_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == 4, (
        f"Expected exactly 4 lines in {OUTPUT_PATH}, got {len(actual_lines)}."
    )
    for i, (wanted, actual) in enumerate(zip(expected, actual_lines)):
        assert actual == wanted, (
            f"Mismatch on line {i + 1}.\nExpected: '{wanted}'\nActual:   '{actual}'"
        )


def run_program():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [BINARY_PATH], cwd='/home/user', capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_analysis_program_and_output_correctness():
    assert os.path.lexists(SOURCE_PATH), f"Source file missing: {SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), (
        f"Source must be a regular file: {SOURCE_PATH}"
    )
    assert os.path.getsize(SOURCE_PATH) > 0, f"Source file is empty: {SOURCE_PATH}"
    assert os.path.isfile(CSV_PATH), f"CSV file missing: {CSV_PATH}"

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', BINARY_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    original_expected = expected_lines(CSV_PATH)

    try:
        # Execute the submitted program on the supplied signal and retain all of
        # the original verifier's exact output assertions.
        run_program()
        assert_output(original_expected)

        # Replace the sampled energies with an unpredictable signal while
        # retaining the required domain. This verifies that the executable
        # actually reads and numerically processes the CSV rather than printing
        # the four known answers.
        xs, ys = read_csv(CSV_PATH)
        rng = secrets.SystemRandom()
        a = rng.uniform(1.2, 2.8)
        b = rng.uniform(-0.9, 0.9)
        c = rng.uniform(0.6, 1.6)
        phase = rng.uniform(0.15, 1.1)
        changed_ys = [
            y + a * math.sin(0.73 * x + phase) + b * x + c * math.cos(1.31 * x)
            for x, y in zip(xs, ys)
        ]
        with open(CSV_PATH, 'w') as f:
            f.write('x,E\n')
            for x, y in zip(xs, changed_ys):
                f.write(f'{x:.12f},{y:.12f}\n')

        changed_expected = expected_lines(CSV_PATH)
        assert changed_expected != original_expected
        run_program()
        assert_output(changed_expected)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        subprocess.run(
            [BINARY_PATH], cwd='/home/user', capture_output=True, text=True, timeout=15
        )

    # Leave and recheck the required final output for the original supplied CSV.
    assert_output(original_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
