#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import subprocess
import tempfile

import h5py
import numpy as np


def test_01_stats_txt_exists_and_content():
    stats_path = "/home/user/stats.txt"
    assert os.path.isfile(stats_path), f"File not found: {stats_path}"

    with open(stats_path, "r") as f:
        content = f.read().strip()

    expected_mean = 8.67
    expected_variance = 6.22
    expected_max_abs_diff = 4.00

    mean_match = re.search(r"Mean:\s*([0-9.]+)", content)
    var_match = re.search(r"Variance:\s*([0-9.]+)", content)
    diff_match = re.search(r"Max_Abs_Diff:\s*([0-9.]+)", content)

    assert mean_match, "Could not find 'Mean: <value>' in stats.txt"
    assert var_match, "Could not find 'Variance: <value>' in stats.txt"
    assert diff_match, "Could not find 'Max_Abs_Diff: <value>' in stats.txt"

    actual_mean = float(mean_match.group(1))
    actual_var = float(var_match.group(1))
    actual_diff = float(diff_match.group(1))

    assert abs(actual_mean - expected_mean) < 0.015, f"Expected Mean ~ {expected_mean}, got {actual_mean}"
    assert abs(actual_var - expected_variance) < 0.015, f"Expected Variance ~ {expected_variance}, got {actual_var}"
    assert abs(actual_diff - expected_max_abs_diff) < 0.015, f"Expected Max_Abs_Diff ~ {expected_max_abs_diff}, got {actual_diff}"


def test_02_c_source_code_exists():
    c_path = "/home/user/process.c"
    assert os.path.isfile(c_path), f"C source file not found at {c_path}"


def _expected(lengths, weights):
    weighted = [length * weight for length, weight in zip(lengths, weights)]
    mean = sum(weighted) / len(weighted)
    variance = sum((value - mean) ** 2 for value in weighted) / len(weighted)
    max_abs_diff = max(abs(weighted[i + 1] - weighted[i]) for i in range(len(weighted) - 1))
    return mean, variance, max_abs_diff


def _check_stats(expected):
    stats_path = "/home/user/stats.txt"
    assert os.path.isfile(stats_path), "The executed program did not create /home/user/stats.txt"
    with open(stats_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    match = re.fullmatch(
        r"Mean: (-?\d+\.\d{2})\n"
        r"Variance: (-?\d+\.\d{2})\n"
        r"Max_Abs_Diff: (-?\d+\.\d{2})",
        content,
    )
    assert match, f"stats.txt does not have the required exact three-line format: {content!r}"

    actual = tuple(float(value) for value in match.groups())
    for label, got, want in zip(("Mean", "Variance", "Max_Abs_Diff"), actual, expected):
        assert math.isfinite(got), f"{label} is not finite"
        assert abs(got - want) <= 0.0051, f"Incorrect {label}: expected {want:.2f}, got {got:.2f}"


def _write_fixture(lengths, weights, rng):
    with open("/home/user/data.fasta", "w", encoding="ascii") as f:
        for i, length in enumerate(lengths):
            f.write(f">generated_sequence_{i}\n")
            sequence = "".join(rng.choice("ACGT") for _ in range(length))
            width = rng.randint(3, 9)
            for start in range(0, length, width):
                f.write(sequence[start:start + width] + "\n")

    with h5py.File("/home/user/ref.h5", "w") as h5:
        h5.create_dataset("weights", data=np.asarray(weights, dtype=np.float64))


def _run(executable):
    try:
        os.remove("/home/user/stats.txt")
    except FileNotFoundError:
        pass
    result = subprocess.run([executable], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_03_compile_and_exercise_program():
    source = "/home/user/process.c"
    fasta = "/home/user/data.fasta"
    hdf5 = "/home/user/ref.h5"
    stats = "/home/user/stats.txt"

    backups = {}
    for path in (fasta, hdf5, stats):
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()

    fd, executable = tempfile.mkstemp(prefix="verified_process_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)

    try:
        compile_result = subprocess.run(
            ["h5cc", "-std=c11", "-O2", source, "-lm", "-o", executable],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"process.c did not compile with HDF5.\n"
            f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compiler did not produce an executable"

        # Execute the submitted program against the original files first.
        _run(executable)
        _check_stats(_expected([8, 4, 12], [1.5, 2.0, 0.5]))

        # Use runtime-generated fixtures so hardcoded output cannot pass.
        rng = random.Random(secrets.randbits(128))
        for _ in range(4):
            count = rng.randint(3, 7)
            lengths = [rng.randint(2, 35) for _ in range(count)]
            weights = [rng.randint(20, 500) / 137.0 for _ in range(count)]
            _write_fixture(lengths, weights, rng)
            _run(executable)
            _check_stats(_expected(lengths, weights))
    finally:
        for path in (fasta, hdf5, stats):
            if path in backups:
                with open(path, "wb") as f:
                    f.write(backups[path])
            else:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
        try:
            os.remove(executable)
        except FileNotFoundError:
            pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
