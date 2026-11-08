#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import itertools
import math
import os
from pathlib import Path
import random
import subprocess
import tempfile

import pytest

HOME = Path("/home/user")
CRASH = HOME / "minimized_crash.csv"
BUGGY = HOME / "sensor_aggregator_buggy"
FIXED = HOME / "sensor_aggregator"
FIXED_OUTPUT = HOME / "fixed_output.txt"

BUGGY_SOURCE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    double sum = 0, sum_sq = 0, val;
    int count = 0;
    while (fscanf(f, "%lf", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        count++;
    }
    fclose(f);
    if (count == 0) {
        printf("0.000000\n");
        return 0;
    }
    double mean = sum / count;
    double variance = (sum_sq / count) - (mean * mean);
    printf("%f\n", sqrt(variance));
    return 0;
}
'''


def run(binary, input_path):
    return subprocess.run(
        [str(binary), str(input_path)], capture_output=True, text=True, timeout=5
    )


def parse_single_number(output):
    text = output.strip()
    try:
        value = float(text)
    except ValueError:
        pytest.fail(f"Output is not a single valid float: {text!r}")
    assert math.isfinite(value), f"Output is not finite: {text!r}"
    assert value >= 0, f"Standard deviation is negative: {value}"
    return value


@pytest.fixture(scope="session")
def trusted_buggy(tmp_path_factory):
    directory = tmp_path_factory.mktemp("trusted_buggy")
    source = directory / "buggy.c"
    binary = directory / "buggy"
    source.write_text(BUGGY_SOURCE)
    result = subprocess.run(
        ["gcc", "-O0", "-o", str(binary), str(source), "-lm"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return binary


@pytest.fixture(scope="session")
def fixed_binary():
    assert (HOME / "sensor_aggregator.c").is_file(), "Fixed C source is missing"
    assert (HOME / "Makefile").is_file(), "Makefile is missing"
    if FIXED.exists():
        FIXED.unlink()
    result = subprocess.run(
        ["make", "-C", str(HOME)], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"Recompilation failed:\n{result.stdout}\n{result.stderr}"
    assert os.access(FIXED, os.X_OK), f"Fixed binary not executable: {FIXED}"
    return FIXED


def test_fuzzer_was_written():
    candidates = []
    for path in HOME.rglob("*"):
        if not path.is_file() or path == HOME / "sensor_aggregator.c":
            continue
        if path.suffix.lower() not in {".py", ".c", ".sh"}:
            continue
        try:
            content = path.read_text(errors="replace")
        except OSError:
            continue
        if "fuzz" in path.name.lower() or "sensor_aggregator_buggy" in content:
            candidates.append((path, content))

    assert candidates, "No fuzzer source file was written"
    valid = []
    errors = []
    for path, content in candidates:
        assert content.strip(), f"Fuzzer source is empty: {path}"
        if path.suffix.lower() == ".py":
            command = ["python3", "-m", "py_compile", str(path)]
        elif path.suffix.lower() == ".sh":
            command = ["bash", "-n", str(path)]
        else:
            command = ["gcc", "-fsyntax-only", str(path)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            valid.append(path)
        else:
            errors.append(f"{path}: {result.stderr}")
    assert valid, "No syntactically valid fuzzer source found:\n" + "\n".join(errors)


def test_minimized_crash_triggers_nan_and_is_minimal(trusted_buggy, tmp_path):
    assert CRASH.exists(), f"Minimized crash file missing: {CRASH}"
    assert os.access(BUGGY, os.X_OK), f"Buggy binary not executable: {BUGGY}"

    # Preserve the original assertion against the provided buggy binary.
    result = run(BUGGY, CRASH)
    assert result.returncode == 0, "Buggy binary failed to execute on minimized_crash.csv"
    assert result.stdout.strip().lower() == "nan", (
        f"Expected buggy binary to output 'nan', but got: {result.stdout.strip().lower()}"
    )

    raw_lines = CRASH.read_text().splitlines()
    assert raw_lines, "minimized_crash.csv is empty"
    values = []
    for line in raw_lines:
        fields = line.split()
        assert len(fields) == 1, "Crash input must contain exactly one float per line"
        try:
            value = float(fields[0])
        except ValueError:
            pytest.fail(f"Invalid float in minimized_crash.csv: {line!r}")
        assert math.isfinite(value), "Crash input may not use nan or infinity as input"
        values.append(value)

    # Check against a verifier-built copy of the authentic original implementation.
    result = run(trusted_buggy, CRASH)
    assert result.returncode == 0
    assert result.stdout.strip().lower() == "nan", (
        "minimized_crash.csv does not trigger nan in the authentic buggy implementation"
    )

    # Delta-debugging minimality: no proper subset may retain the failure. Exhaustively
    # check manageable inputs and at least all one-line deletions for larger inputs.
    indexes = range(len(raw_lines))
    if len(raw_lines) <= 12:
        subsets = (
            subset
            for size in range(len(raw_lines))
            for subset in itertools.combinations(indexes, size)
        )
    else:
        subsets = (tuple(j for j in indexes if j != i) for i in indexes)

    for number, subset in enumerate(subsets):
        candidate = tmp_path / f"reduced_{number}.csv"
        candidate.write_text("".join(raw_lines[i] + "\n" for i in subset))
        reduced = run(trusted_buggy, candidate)
        assert reduced.returncode == 0
        assert reduced.stdout.strip().lower() != "nan", (
            "minimized_crash.csv is not minimal: a proper subset of its lines still triggers nan"
        )


def test_fixed_output_file_matches_fixed_run(fixed_binary):
    assert FIXED_OUTPUT.exists(), f"Fixed output file missing: {FIXED_OUTPUT}"
    content = FIXED_OUTPUT.read_text().strip()

    # Preserve the original checks and additionally reject infinities.
    try:
        value = float(content)
        assert not math.isnan(value), "fixed_output.txt contains 'nan'"
        assert value >= 0, "Standard deviation cannot be negative"
    except ValueError:
        pytest.fail(f"fixed_output.txt does not contain a valid float: {content}")
    assert math.isfinite(value), "fixed_output.txt must contain a finite result"

    result = run(fixed_binary, CRASH)
    assert result.returncode == 0, "Fixed binary failed on minimized_crash.csv"
    parse_single_number(result.stdout)
    assert result.stdout.strip() == content, (
        "fixed_output.txt is not the saved stdout of the rebuilt fixed binary on minimized_crash.csv"
    )


def expected_stddev(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((x - mean) * (x - mean) for x in values) / len(values)
    return math.sqrt(variance)


def check_dataset(binary, tmp_path, name, values):
    path = tmp_path / f"{name}_{random.SystemRandom().getrandbits(64):016x}.csv"
    path.write_text("".join(f"{value:.17g}\n" for value in values))
    parsed = [float(line) for line in path.read_text().splitlines()]
    expected = expected_stddev(parsed)
    result = run(binary, path)
    assert result.returncode == 0, f"Fixed binary failed on hidden dataset {name}"
    actual = parse_single_number(result.stdout)
    tolerance = max(2e-5, abs(expected) * 2e-5)
    assert math.isclose(actual, expected, rel_tol=2e-5, abs_tol=tolerance), (
        f"Incorrect standard deviation for {name}: got {actual}, expected {expected}"
    )
    return actual


def test_fixed_binary_solves_cancellation_and_general_inputs(fixed_binary, tmp_path):
    # Preserve the original cancellation dataset and expected range assertion.
    original = [100000000.0 + i * 0.01 for i in range(100)]
    original_value = check_dataset(fixed_binary, tmp_path, "original_cancellation", original)
    assert 0.28 < original_value < 0.30, (
        f"Fixed binary output {original_value} is far from expected ~0.29"
    )

    # Randomized, verifier-derived cases prevent a fixed output from passing.
    rng = random.SystemRandom()
    cases = []
    for case_number in range(6):
        count = rng.randint(17, 180)
        base = rng.choice([-1.0, 1.0]) * rng.randint(10**11, 10**13)
        step = rng.choice([0.125, 0.25, 0.5, 1.0, 2.0])
        offsets = [rng.randint(-80, 80) for _ in range(count)]
        cases.append((f"large_offset_{case_number}", [base + step * x for x in offsets]))

    cases.extend([
        ("ordinary", [rng.uniform(-5000.0, 9000.0) for _ in range(91)]),
        ("constant_large", [float(rng.randint(10**12, 10**13))] * 37),
        ("two_values", [rng.uniform(-100.0, 100.0), rng.uniform(1000.0, 2000.0)]),
        ("singleton", [rng.uniform(-1e6, 1e6)]),
    ])

    outputs = [check_dataset(fixed_binary, tmp_path, name, values) for name, values in cases]
    assert len({round(value, 5) for value in outputs}) >= 4, "Fixed binary appears to emit a constant"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
