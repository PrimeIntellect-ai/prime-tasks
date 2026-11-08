#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import struct
import subprocess

PROJECT = "/home/user/bio_mcmc"
DATA_PATH = os.path.join(PROJECT, "sequence_likelihoods.txt")
RESULT_PATH = "/home/user/integral_result.txt"
MAIN_PATH = os.path.join(PROJECT, "src/main.rs")


def as_f32(value):
    return struct.unpack('f', struct.pack('f', float(value)))[0]


def expected_from_text(text):
    data = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(',')
        if len(parts) == 2:
            data.append((as_f32(parts[0]), as_f32(parts[1])))

    data.sort(key=lambda item: item[0])
    total = 0.0
    for i in range(len(data) - 1):
        x1, y1 = data[i]
        x2, y2 = data[i + 1]
        total += 0.5 * (float(y1) + float(y2)) * (float(x2) - float(x1))
    return f"{total:.4f}"


def extract_result(text):
    text = text.strip()
    match = re.fullmatch(r"Integral:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)", text)
    assert match, f"Program output was not in the expected 'Integral: <float>' form: {text!r}"
    value = match.group(1)
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", value), f"Integral was not printed to exactly 4 decimal places: {value!r}"
    return value


def run_binary(binary):
    completed = subprocess.run(
        [binary], cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"Rust program failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return extract_result(completed.stdout)


def test_integral_result_file_exists():
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} does not exist. Did you run the Rust project and save the output?"


def test_integral_result_value():
    assert os.path.isfile(DATA_PATH), f"Data file {DATA_PATH} is missing."
    with open(DATA_PATH, 'r') as f:
        expected_str = expected_from_text(f.read())

    with open(RESULT_PATH, 'r') as f:
        actual_str = f.read().strip()

    if "Integral:" in actual_str:
        actual_str = actual_str.split("Integral:")[1].strip()

    assert actual_str == expected_str, f"Expected integral result to be {expected_str}, but got {actual_str}"


def test_rust_code_modifications():
    assert os.path.isfile(MAIN_PATH), f"File {MAIN_PATH} is missing."
    with open(MAIN_PATH, 'r') as f:
        content = f.read()

    assert "f64" in content, "The Rust code does not appear to use f64 for the accumulation as requested."
    assert "into_par_iter" not in content, "The Rust code still seems to use unordered parallel iteration (`into_par_iter`). It should be sequential."
    assert re.search(r"\bfn\s+calculate_integral\s*\(", content), "The calculate_integral function is missing."
    assert len(re.findall(r"\bcalculate_integral\s*\(", content)) >= 2, "calculate_integral does not appear to be called by the program."


def test_compiled_program_and_calculate_integral_behavior():
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        build = subprocess.run(
            ["cargo", "build", "--quiet"], cwd=PROJECT,
            text=True, capture_output=True, timeout=180
        )
        assert build.returncode == 0, (
            f"Rust project did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
        )

        binary = os.path.join(PROJECT, "target", "debug", "bio_mcmc")
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Cargo did not produce an executable bio_mcmc binary."

        original_text = original_data.decode()
        assert run_binary(binary) == expected_from_text(original_text), "The compiled program produced the wrong result for the supplied dataset."

        seed = int.from_bytes(os.urandom(16), "big")
        rng = random.Random(seed)

        # Unsorted, irregular input checks sorting and the standard trapezoidal formula.
        points = []
        x = 0.0
        for _ in range(137):
            x += rng.uniform(0.015, 1.25)
            y = rng.uniform(0.001, 25.0)
            points.append((x, y))
        rng.shuffle(points)
        probe1 = "".join(f"{x:.12f},{y:.12f}\n" for x, y in points)

        # A large positive sum makes f32 accumulation lose substantial low-order
        # information while remaining straightforward for sequential f64 summation.
        points = []
        for i in range(12000):
            x = i * 0.25
            y = 100000.0 + rng.uniform(-4000.0, 4000.0) + (i % 17) * 0.03125
            points.append((x, y))
        rng.shuffle(points)
        probe2 = "".join(f"{x:.8f},{y:.10f}\n" for x, y in points)

        for number, probe in enumerate((probe1, probe2), 1):
            with open(DATA_PATH, 'w') as f:
                f.write(probe)
            actual = run_binary(binary)
            expected = expected_from_text(probe)
            assert actual == expected, f"Behavioral probe {number}: expected {expected}, got {actual}"
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
