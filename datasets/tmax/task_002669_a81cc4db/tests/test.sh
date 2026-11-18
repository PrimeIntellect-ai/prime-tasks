#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import statistics
import subprocess
from decimal import Decimal, ROUND_HALF_EVEN
from fractions import Fraction

ETL = "/home/user/etl"
DATA = os.path.join(ETL, "data.csv")
RESULTS = os.path.join(ETL, "results.csv")
AGG_SRC = os.path.join(ETL, "aggregator.cpp")
AGG_EXE = os.path.join(ETL, "aggregator")
TEST_SRC = os.path.join(ETL, "test_aggregator.cpp")
TEST_EXE = os.path.join(ETL, "run_tests")
METRICS = os.path.join(ETL, "metrics.txt")

ORIGINAL_ROWS = [
    ("cat_A", "9007199254740993"),
    ("cat_B", "9007199254740995"),
    ("cat_A", ""),
    ("cat_B", "2"),
    ("cat_C", "10000000000000000"),
    ("cat_C", "5"),
]
ORIGINAL_EXPECTED = {
    "cat_A": 9007199254740993,
    "cat_B": 9007199254740997,
    "cat_C": 10000000000000005,
}


def run(cmd, timeout=20):
    return subprocess.run(cmd, cwd=ETL, capture_output=True, text=True, timeout=timeout)


def write_rows(rows):
    with open(DATA, "w", encoding="utf-8", newline="") as f:
        for category, value in rows:
            f.write(f"{category},{value}\n")


def read_results():
    assert os.path.isfile(RESULTS), f"File {RESULTS} does not exist."
    actual = {}
    with open(RESULTS, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid format in results.csv: {line}"
            category, value = parts
            assert category not in actual, f"Duplicate category in results.csv: {category}"
            assert re.fullmatch(r"[0-9]+", value), f"Invalid unsigned sum: {value}"
            actual[category] = int(value)
    return actual


def execute_aggregator(executable, rows, expected):
    write_rows(rows)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    result = run([executable])
    assert result.returncode == 0, (
        f"{executable} exited with code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    actual = read_results()
    assert actual == expected, f"results.csv data does not match expected values. Got {actual}"


def parse_metrics(path):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    mean_match = re.search(r"Mean:\s*([0-9.]+)", content)
    assert mean_match is not None, "Mean not found in metrics.txt in the expected format."
    var_match = re.search(r"Variance:\s*([0-9.eE+]+)", content)
    assert var_match is not None, "Variance not found in metrics.txt in the expected format."
    return content, mean_match.group(1), var_match.group(1)


def rounded_fraction(value):
    return (Decimal(value.numerator) / Decimal(value.denominator)).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_EVEN
    )


def locate_metrics_scripts():
    candidates = []
    excluded = {os.path.basename(AGG_SRC), os.path.basename(TEST_SRC)}
    for name in os.listdir(ETL):
        path = os.path.join(ETL, name)
        if not os.path.isfile(path) or name in excluded:
            continue
        if name.endswith((".py", ".cpp", ".cc", ".cxx")):
            try:
                content = open(path, "r", encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            if "results.csv" in content and "metrics.txt" in content:
                candidates.append(path)
    return candidates


def execute_metrics_script(expected):
    candidates = locate_metrics_scripts()
    assert candidates, "No Python or C++ statistical tracking script was found."

    values = list(expected.values())
    count = len(values)
    mean = Fraction(sum(values), count)
    variance = sum((Fraction(v) - mean) ** 2 for v in values) / (count - 1)
    expected_mean = rounded_fraction(mean)
    expected_variance = rounded_fraction(variance)
    failures = []

    for index, candidate in enumerate(candidates):
        try:
            if os.path.exists(METRICS):
                os.remove(METRICS)
            if candidate.endswith(".py"):
                result = run(["python3", candidate])
            else:
                binary = f"/tmp/metrics_script_{index}"
                compiled = run(["g++", "-std=c++17", "-O2", candidate, "-o", binary])
                if compiled.returncode != 0:
                    failures.append(f"{candidate}: compilation failed: {compiled.stderr}")
                    continue
                result = run([binary])
            if result.returncode != 0:
                failures.append(f"{candidate}: exited {result.returncode}: {result.stderr}")
                continue
            _, mean_text, variance_text = parse_metrics(METRICS)
            if Decimal(mean_text) != expected_mean:
                failures.append(f"{candidate}: expected mean {expected_mean}, got {mean_text}")
                continue
            if Decimal(variance_text) != expected_variance:
                failures.append(
                    f"{candidate}: expected variance {expected_variance}, got {variance_text}"
                )
                continue
            return
        except Exception as exc:
            failures.append(f"{candidate}: {exc}")

    raise AssertionError("No statistical tracking script produced correct dynamic metrics: " + " | ".join(failures))


def test_complete_etl_workflow():
    # Preserve the original source-level assertions.
    assert os.path.isfile(AGG_SRC), f"File {AGG_SRC} does not exist."
    with open(AGG_SRC, "r", encoding="utf-8") as f:
        content = f.read()
    assert "stoull" in content, "aggregator.cpp does not use std::stoull as requested."
    assert "stod" not in content, "aggregator.cpp still contains std::stod."

    # Preserve executable/file assertions and ensure the requested compiled artifacts are ELF files.
    assert os.path.isfile(AGG_EXE), f"Executable {AGG_EXE} does not exist."
    assert os.access(AGG_EXE, os.X_OK), f"File {AGG_EXE} is not executable."
    with open(AGG_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "aggregator is not a compiled executable."

    assert os.path.isfile(TEST_SRC), f"Test file {TEST_SRC} does not exist."
    assert os.path.isfile(TEST_EXE), f"Test executable {TEST_EXE} does not exist."
    assert os.access(TEST_EXE, os.X_OK), f"File {TEST_EXE} is not executable."
    with open(TEST_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "run_tests is not a compiled executable."

    # Recreate the specified input and actually execute the submitted aggregator.
    execute_aggregator(AGG_EXE, ORIGINAL_ROWS, ORIGINAL_EXPECTED)

    # Preserve the original metrics assertions for the specified dataset.
    _, mean_text, variance_text = parse_metrics(METRICS)
    values = list(ORIGINAL_EXPECTED.values())
    expected_mean = statistics.mean(values)
    expected_variance = statistics.variance(values)
    actual_mean = float(mean_text)
    actual_variance = float(variance_text)
    assert abs(actual_mean - expected_mean) < 0.1, (
        f"Expected mean ~{expected_mean:.2f}, got {actual_mean}"
    )
    rel_error = abs(actual_variance - expected_variance) / expected_variance
    assert rel_error < 0.01, (
        f"Expected variance ~{expected_variance:.2e}, got {actual_variance}"
    )

    # Run the submitted test executable, then independently compile and run its source.
    result = run([TEST_EXE])
    assert result.returncode == 0, f"run_tests exited with code {result.returncode}, expected 0."
    rebuilt_tests = "/tmp/run_tests_rebuilt"
    compiled = run(["g++", "-std=c++17", "-O2", TEST_SRC, "-o", rebuilt_tests])
    assert compiled.returncode == 0, f"test_aggregator.cpp does not compile: {compiled.stderr}"
    result = run([rebuilt_tests])
    assert result.returncode == 0, (
        f"Freshly compiled test_aggregator.cpp exited with {result.returncode}."
    )

    # Independently compile aggregator.cpp so both the submitted binary and source are exercised.
    rebuilt_aggregator = "/tmp/aggregator_rebuilt"
    compiled = run(["g++", "-std=c++17", "-O2", AGG_SRC, "-o", rebuilt_aggregator])
    assert compiled.returncode == 0, f"aggregator.cpp does not compile: {compiled.stderr}"

    token = secrets.token_hex(8)
    rows = []
    dynamic_expected = {}
    for index in range(4):
        category = f"verify_{token}_{index}"
        first = (1 << 53) + secrets.randbelow(1 << 42) * 2 + 1
        second = (1 << 54) + secrets.randbelow(1 << 42) * 2 + 1
        rows.extend([(category, str(first)), (category, ""), (category, str(second))])
        dynamic_expected[category] = first + second

    # Runtime-generated categories and values prevent fixed-output implementations from passing.
    execute_aggregator(AGG_EXE, rows, dynamic_expected)
    execute_aggregator(rebuilt_aggregator, rows, dynamic_expected)

    # Execute the requested statistics script against the dynamic aggregation output.
    execute_metrics_script(dynamic_expected)

    # Leave the requested files populated for the original supplied dataset.
    execute_aggregator(AGG_EXE, ORIGINAL_ROWS, ORIGINAL_EXPECTED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
