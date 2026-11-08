#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
from pathlib import Path
import random
import subprocess


def test_correlation_file_exists():
    """Test that the correlation.txt file exists."""
    file_path = "/home/user/correlation.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."


def test_correlation_value():
    """Test that correlation.txt contains the correct value for the supplied log."""
    file_path = "/home/user/correlation.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_value = "-0.9594"
    assert content == expected_value, \
        f"Expected correlation value '{expected_value}', but got '{content}'."

    with open(file_path, "rb") as f:
        assert f.read() == b"-0.9594\n", \
            "correlation.txt must contain exactly four decimal places and a newline."


def pearson(xs, ys):
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mean_x) ** 2 for x in xs) *
        sum((y - mean_y) ** 2 for y in ys)
    )
    return numerator / denominator


def make_random_log(rng, trial):
    count = 7 + trial
    xs = [rng.uniform(0.01, 9.0) for _ in range(count)]
    slope = rng.choice([-1.0, 1.0]) * rng.uniform(0.4, 2.5)
    ys = [slope * x + rng.uniform(-2.0, 2.0) for x in xs]
    lines = []
    for i, (x, y) in enumerate(zip(xs, ys)):
        lines.append(
            f"[INFO] Exp_ID: T{trial}_{i} | LR: {x:.8f} | "
            f"BS: {32 * (1 + i % 4)} | ValLoss: {y:.8f} | "
            f"Acc: {rng.uniform(0.5, 0.99):.6f}"
        )

    # Derive the expected result from the exact decimal values written to disk.
    written_xs = [float(f"{x:.8f}") for x in xs]
    written_ys = [float(f"{y:.8f}") for y in ys]
    expected = f"{pearson(written_xs, written_ys):.4f}\n".encode()
    return ("\n".join(lines) + "\n").encode(), expected


def test_cpp_program_compiles_and_computes_from_log():
    home = Path("/home/user")
    log_path = home / "experiment_logs.txt"
    output_path = home / "correlation.txt"

    candidates = []
    preferred = home / "analyze.cpp"
    if preferred.is_file():
        candidates.append(preferred)
    for extension in ("*.cpp", "*.cc", "*.cxx"):
        for path in sorted(home.rglob(extension)):
            if path.is_file() and path not in candidates:
                candidates.append(path)

    assert candidates, "No C++ source program was found under /home/user."

    original_log = log_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.exists() else None
    failures = []
    rng = random.SystemRandom()

    try:
        for index, source in enumerate(candidates):
            executable = Path(f"/tmp/correlation_analyzer_{index}")
            try:
                compiled = subprocess.run(
                    ["g++", "-std=c++17", str(source), "-o", str(executable)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                if compiled.returncode != 0:
                    failures.append(f"{source}: compilation failed: {compiled.stderr[-500:]}")
                    continue

                for trial in range(2):
                    log_data, expected = make_random_log(rng, trial)
                    log_path.write_bytes(log_data)
                    if output_path.exists():
                        output_path.unlink()

                    result = subprocess.run(
                        [str(executable)],
                        cwd=str(home),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=15,
                    )
                    assert result.returncode == 0, \
                        f"program exited with status {result.returncode}: {result.stderr[-500:]}"
                    assert output_path.is_file(), \
                        "executing the C++ program did not create /home/user/correlation.txt"
                    actual = output_path.read_bytes()
                    assert actual == expected, \
                        f"for a generated log, expected {expected!r}, but got {actual!r}"

                return
            except (AssertionError, subprocess.TimeoutExpired, OSError) as exc:
                failures.append(f"{source}: {exc}")
            finally:
                if executable.exists():
                    executable.unlink()

        raise AssertionError(
            "No submitted C++ source compiled and correctly computed Pearson "
            "correlation on generated logs. " + " | ".join(failures)
        )
    finally:
        log_path.write_bytes(original_log)
        if original_output is None:
            if output_path.exists():
                output_path.unlink()
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
