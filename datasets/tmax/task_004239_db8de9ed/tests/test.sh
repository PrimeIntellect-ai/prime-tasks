#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess

SOURCE = '/home/user/compute_integral.rs'
DATA = '/home/user/data/affinities.bin'
RESULTS = '/home/user/results.txt'
BINARY = '/tmp/compute_integral_submission'


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def kahan_expected(values):
    total = f32(0.0)
    compensation = f32(0.0)
    checkpoints = []
    for index, value in enumerate(values):
        y = f32(value - compensation)
        updated = f32(total + y)
        compensation = f32(f32(updated - total) - y)
        total = updated
        if (index + 1) % 100000 == 0:
            checkpoints.append(total)
    return [f'{total:.4f}'] + [f'{value:.4f}' for value in checkpoints]


def read_result_lines():
    with open(RESULTS, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def run_submission():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run([BINARY], cwd='/home/user', timeout=30,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True)
    assert completed.returncode == 0, (
        f'Compiled Rust program exited with status {completed.returncode}. '
        f'stderr: {completed.stderr}'
    )


def write_original_data():
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    packed = struct.pack('<f', 1.23456e-4)
    with open(DATA, 'wb') as f:
        f.write(packed * 1000000)


def test_results_file_exists():
    """Check if the results.txt file was created."""
    assert os.path.isfile(RESULTS), f"File {RESULTS} is missing. Did you run the Rust program?"


def test_results_content():
    """Verify the contents of results.txt match the expected Kahan summation output."""
    lines = read_result_lines()
    assert len(lines) == 11, f"Expected exactly 11 lines of output, but found {len(lines)}."

    val = 1.23456e-4
    expected_lines = [f"{val * 1000000:.4f}"]
    for i in range(1, 11):
        expected_lines.append(f"{val * (i * 100000):.4f}")

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} is incorrect. Expected '{expected}', got '{actual}'. "
            "This indicates precision loss or incorrect formatting."
        )


def test_compiled_program_computes_input_with_kahan_summation():
    assert os.path.isfile(SOURCE), f'Required Rust source file {SOURCE} is missing.'
    assert os.path.getsize(SOURCE) > 0, f'Required Rust source file {SOURCE} is empty.'

    compiled = subprocess.run(['rustc', '-O', SOURCE, '-o', BINARY], timeout=60,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True)
    assert compiled.returncode == 0, f'Rust source did not compile: {compiled.stderr}'
    assert os.path.isfile(BINARY), 'rustc did not produce an executable program.'

    # Preserve the original fixed-data assertions, but obtain results by running
    # the submitted artifact rather than trusting a pre-created results file.
    write_original_data()
    run_submission()
    test_results_file_exists()
    test_results_content()

    # Replace the input with values unknown while the agent was running. Their
    # f32 reduction loses visible precision with an ordinary f32 += loop.
    rng = random.Random(int.from_bytes(os.urandom(16), 'little'))
    values = []
    with open(DATA, 'wb') as f:
        for _ in range(1000000):
            value = f32((500000 + rng.randrange(1000001)) * 1.0e-10)
            values.append(value)
            f.write(struct.pack('<f', value))

    expected = kahan_expected(values)
    run_submission()
    test_results_file_exists()
    actual = read_result_lines()
    assert len(actual) == 11, f'Expected exactly 11 lines of output, but found {len(actual)}.'
    assert actual == expected, (
        'Output from the compiled program does not match f32 Kahan cumulative '
        f'summation for verifier-generated input. Expected {expected}, got {actual}.'
    )

    # Leave the requested result for the original task input in the final state.
    write_original_data()
    run_submission()
    test_results_file_exists()
    test_results_content()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
