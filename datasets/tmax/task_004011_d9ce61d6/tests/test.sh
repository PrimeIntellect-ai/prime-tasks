#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/detector"
SOURCE = "/home/user/detector.c"
B = 2000
THRESHOLD = 2.50


def run_detector(executable, path):
    result = subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, f"Detector exited with {result.returncode} for {path}"
    return result.stdout.strip()


def test_detector_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."


def test_evil_corpus_rejected():
    if not os.path.isfile(EXECUTABLE) or not os.access(EXECUTABLE, os.X_OK):
        pytest.fail("Detector executable is missing or not executable.")

    evil_files = glob.glob("/app/corpora/evil/*.csv")
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed = []
    for path in evil_files:
        try:
            if run_detector(EXECUTABLE, path) != "REJECT":
                bypassed.append(os.path.basename(path))
        except Exception as exc:
            bypassed.append(f"{os.path.basename(path)} (error: {exc})")

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil bypassed. "
            f"Offending files: {', '.join(bypassed)}"
        )


def test_clean_corpus_accepted():
    if not os.path.isfile(EXECUTABLE) or not os.access(EXECUTABLE, os.X_OK):
        pytest.fail("Detector executable is missing or not executable.")

    clean_files = glob.glob("/app/corpora/clean/*.csv")
    assert len(clean_files) > 0, "No clean corpus files found."

    modified = []
    for path in clean_files:
        try:
            if run_detector(EXECUTABLE, path) != "ACCEPT":
                modified.append(os.path.basename(path))
        except Exception as exc:
            modified.append(f"{os.path.basename(path)} (error: {exc})")

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_files)} clean modified. "
            f"Offending files: {', '.join(modified)}"
        )


def bootstrap_lower(differences):
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.restype = ctypes.c_int
    libc.srand(42)

    count = len(differences)
    means = []
    for _ in range(B):
        total = 0.0
        for _ in range(count):
            total += differences[libc.rand() % count]
        means.append(total / count)
    means.sort()
    return means[int(0.025 * B)]


def make_shifted_differences(rng, count, desired_lower):
    base = [rng.uniform(1.0, 5.0) for _ in range(count)]
    shift = desired_lower - bootstrap_lower(base)
    shifted = [value + shift for value in base]
    assert min(shifted) > 0.0
    return shifted


def write_csv(path, target_differences, other_difference, rng):
    values = [rng.uniform(-10.0, 10.0) for _ in range(3)]
    rows = [tuple(values)]
    for difference in target_differences:
        values[0] += rng.choice((-1.0, 1.0)) * other_difference
        values[1] += rng.choice((-1.0, 1.0)) * difference
        values[2] += rng.choice((-1.0, 1.0)) * other_difference
        rows.append(tuple(values))

    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(f"{row[0]:.10f},{row[1]:.10f},{row[2]:.10f}\n")


def differences_from_file(path):
    values = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            fields = line.strip().split(",")
            assert len(fields) == 3
            values.append(float(fields[1]))
    return [abs(values[i] - values[i - 1]) for i in range(1, len(values))]


def test_generated_inputs_and_rebuilt_c_source():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."
    workdir = tempfile.mkdtemp(prefix="telemetry_")
    rebuilt = os.path.join(workdir, secrets.token_hex(8))
    compilation = subprocess.run(
        ["gcc", "-O3", SOURCE, "-lm", "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compilation.returncode == 0, f"detector.c did not compile: {compilation.stderr}"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    specifications = [
        (make_shifted_differences(rng, 82, 2.30), 4.25),
        (make_shifted_differences(rng, 98, 2.70), 0.20),
        (make_shifted_differences(rng, 126, 2.32), 4.00),
        (make_shifted_differences(rng, 73, 2.68), 0.15),
        ([rng.uniform(0.10, 0.70) for _ in range(54)], 4.50),
        ([rng.uniform(3.20, 4.40) for _ in range(111)], 0.10),
    ]

    cases = []
    for target_differences, other_difference in specifications:
        path = os.path.join(workdir, secrets.token_hex(12) + ".csv")
        write_csv(path, target_differences, other_difference, rng)
        actual_differences = differences_from_file(path)
        lower = bootstrap_lower(actual_differences)
        assert abs(lower - THRESHOLD) > 0.10, "Generated case is too close to threshold"
        expected = "REJECT" if lower > THRESHOLD else "ACCEPT"
        cases.append((path, expected))

    random.SystemRandom().shuffle(cases)
    assert {expected for _, expected in cases} == {"ACCEPT", "REJECT"}

    for executable in (EXECUTABLE, rebuilt):
        for path, expected in cases:
            output = run_detector(executable, path)
            assert output == expected, (
                f"{executable} returned {output!r}, expected {expected!r} "
                f"for generated input {path}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
