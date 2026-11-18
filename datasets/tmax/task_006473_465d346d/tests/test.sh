#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_aggregator.py
import json
import math
import os
import random
import shutil
import subprocess
import tempfile

AGGREGATOR_DIR = "/home/user/aggregator"
SOURCE_PATH = os.path.join(AGGREGATOR_DIR, "main.go")
TRANSACTIONS_PATH = os.path.join(AGGREGATOR_DIR, "transactions.log")
TRACE_LOG_PATH = "/home/user/trace.log"
RESULT_JSON_PATH = "/home/user/result.json"

ORIGINAL_LINES = [
    "1000000.10",
    "1000000.20",
    "1000000.15",
    "1000000.25",
    "1000000.10",
    "CORRUPT_RECORD",
    "1000000.30",
    "1000000.05",
    "1000000.15",
    "1000000.20",
    "1000000.10",
]
ORIGINAL_VALUES = [
    1000000.10, 1000000.20, 1000000.15, 1000000.25, 1000000.10,
    1000000.30, 1000000.05, 1000000.15, 1000000.20, 1000000.10,
]


def remove_outputs():
    for path in (TRACE_LOG_PATH, RESULT_JSON_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def write_transactions(lines):
    with open(TRANSACTIONS_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def run_candidate(binary):
    remove_outputs()
    completed = subprocess.run(
        [binary],
        cwd=AGGREGATOR_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def read_and_check_trace(expected_values):
    assert os.path.isfile(TRACE_LOG_PATH), (
        f"{TRACE_LOG_PATH} is missing. Did the program generate the trace log?"
    )
    with open(TRACE_LOG_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 trace lines, got {len(lines)}."
    for i, expected_val in enumerate(expected_values[:5], start=1):
        line = lines[i - 1]
        prefix = f"Parsed value {i}: "
        assert line.startswith(prefix), (
            f"Line {i} does not start with expected prefix {prefix!r}. Got: {line}"
        )
        val_str = line[len(prefix):]
        try:
            val = float(val_str)
        except ValueError as exc:
            raise AssertionError(
                f"Could not parse float from trace line {i}: {val_str}"
            ) from exc
        assert math.isclose(val, expected_val, rel_tol=1e-9), (
            f"Expected value {expected_val} on line {i}, got {val}"
        )


def read_result():
    assert os.path.isfile(RESULT_JSON_PATH), (
        f"{RESULT_JSON_PATH} is missing. Did the program write the final metrics?"
    )
    try:
        with open(RESULT_JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{RESULT_JSON_PATH} does not contain valid JSON.") from exc

    assert "count" in data, "JSON missing 'count' key."
    assert "mean" in data, "JSON missing 'mean' key."
    assert "variance" in data, "JSON missing 'variance' key."
    return data


def check_original_case(binary):
    write_transactions(ORIGINAL_LINES)
    run_candidate(binary)
    read_and_check_trace(ORIGINAL_VALUES)
    data = read_result()

    assert data["count"] == 10, f"Expected count to be 10, got {data['count']}."
    assert math.isclose(data["mean"], 1000000.16, rel_tol=1e-9), (
        f"Expected mean to be ~1000000.16, got {data['mean']}."
    )
    variance = data["variance"]
    assert isinstance(variance, (int, float)) and math.isfinite(variance), (
        f"Variance must be a finite number, got {variance!r}."
    )
    assert variance > 0, f"Variance must be positive, got {variance}."
    assert math.isclose(variance, 0.0054, rel_tol=1e-5), (
        f"Expected population variance to be ~0.0054, got {variance}. "
        "Ensure you are using a numerically stable algorithm."
    )


def check_generated_case(binary, rng):
    count = rng.randint(8, 14)
    base = rng.randint(100_000_000_000, 900_000_000_000)
    offsets = rng.sample(range(-500, 501), count)
    values = [float(base + offset) for offset in offsets]

    lines = []
    for i, value in enumerate(values):
        if i == 2:
            lines.append("CORRUPT_RECORD")
        if i == 5:
            lines.append("BROKEN_INPUT")
        lines.append(str(int(value)))
    lines.insert(len(lines) - 1, "CORRUPT_RECORD")

    write_transactions(lines)
    run_candidate(binary)
    read_and_check_trace(values)
    data = read_result()

    expected_mean = math.fsum(values) / len(values)
    expected_variance = math.fsum(
        (value - expected_mean) ** 2 for value in values
    ) / len(values)

    assert data["count"] == len(values), (
        f"Expected count {len(values)}, got {data['count']}."
    )
    assert isinstance(data["mean"], (int, float)) and math.isfinite(data["mean"]), (
        f"Mean must be a finite number, got {data['mean']!r}."
    )
    assert math.isclose(data["mean"], expected_mean, rel_tol=0.0, abs_tol=0.002), (
        f"Expected mean {expected_mean}, got {data['mean']}."
    )
    variance = data["variance"]
    assert isinstance(variance, (int, float)) and math.isfinite(variance), (
        f"Variance must be a finite number, got {variance!r}."
    )
    assert variance > 0, f"Variance must be positive, got {variance}."
    assert math.isclose(
        variance,
        expected_variance,
        rel_tol=1e-6,
        abs_tol=0.01,
    ), (
        f"Expected population variance {expected_variance}, got {variance}. "
        "Ensure the calculation is numerically stable."
    )


def main():
    assert os.path.isfile(SOURCE_PATH), f"Required Go source {SOURCE_PATH} is missing."

    fd, binary = tempfile.mkstemp(prefix="aggregator-candidate-")
    os.close(fd)
    os.remove(binary)

    had_transactions = os.path.exists(TRANSACTIONS_PATH)
    original_transactions = None
    if had_transactions:
        with open(TRANSACTIONS_PATH, "rb") as f:
            original_transactions = f.read()

    try:
        build = subprocess.run(
            ["go", "build", "-o", binary, SOURCE_PATH],
            cwd=AGGREGATOR_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, (
            f"Go source failed to build.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
        )
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), (
            "go build did not produce an executable artifact."
        )

        check_original_case(binary)
        rng = random.SystemRandom()
        check_generated_case(binary, rng)
        check_generated_case(binary, rng)
    finally:
        try:
            os.remove(binary)
        except FileNotFoundError:
            pass
        if had_transactions:
            with open(TRANSACTIONS_PATH, "wb") as f:
                f.write(original_transactions)
        else:
            try:
                os.remove(TRANSACTIONS_PATH)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_aggregator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
