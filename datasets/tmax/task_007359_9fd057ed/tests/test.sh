#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import statistics
import subprocess
import tempfile

RESULTS = "/home/user/results.csv"
PROCESSOR = "/home/user/processor"
SOURCE = "/home/user/processor.cpp"
DATA_DIR = "/home/user/data"
DOUBLE_RE = re.compile(r'^[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?$')


def expected_for_file(path):
    values = []
    with open(path, "r") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if "," not in line:
                continue
            value_text = line.split(",", 1)[1].strip()
            if not DOUBLE_RE.fullmatch(value_text):
                continue
            value = float(value_text)
            if math.isfinite(value):
                values.append(value)
    if not values:
        return None
    return statistics.pstdev(values)


def parse_single_output(stdout, expected_path):
    lines = [line for line in stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"Expected one output line for {expected_path}, got: {stdout!r}"
    parts = lines[0].rsplit(",", 1)
    assert len(parts) == 2, f"Malformed processor output: {lines[0]!r}"
    assert parts[0] == expected_path, f"Processor printed wrong filename: {parts[0]!r}"
    try:
        value = float(parts[1])
    except ValueError:
        assert False, f"Processor emitted a non-numeric stddev: {parts[1]!r}"
    assert math.isfinite(value), f"Processor emitted a non-finite stddev: {value}"
    return value


def run_processor(executable, path):
    completed = subprocess.run(
        [executable, path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert completed.returncode == 0, (
        f"{executable} failed on {path} with code {completed.returncode}: "
        f"{completed.stderr}"
    )
    return completed.stdout


def assert_processor_behavior(executable):
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="processor_check_") as td:
        path = os.path.join(td, f"telemetry_{rng.randrange(1 << 60)}.txt")
        offsets = [rng.randrange(-32, 33) / 8.0 for _ in range(13)]
        if len(set(offsets)) < 2:
            offsets[-1] += 1.0
        base = 1_000_000_000_000.0
        expected_values = [base + offset for offset in offsets]
        with open(path, "w") as f:
            f.write("100,\n")
            f.write("101,not-a-number\n")
            f.write("102,12.5junk\n")
            f.write("line-without-comma\n")
            for i, value in enumerate(expected_values):
                f.write(f"{200 + i},{value:.3f}\n")
        actual = parse_single_output(run_processor(executable, path), path)
        expected = statistics.pstdev(expected_values)
        assert math.isclose(actual, expected, rel_tol=2e-5, abs_tol=1e-7), (
            f"Incorrect stable stddev from {executable}: expected {expected}, got {actual}"
        )

        empty_path = os.path.join(td, f"malformed_{rng.randrange(1 << 60)}.txt")
        with open(empty_path, "w") as f:
            f.write("1,\n2,bad\n3,1.0trailing\nno comma\n")
        stdout = run_processor(executable, empty_path)
        assert stdout.strip() == "", "Processor should skip all malformed values without crashing"


def test_results_csv_exists():
    assert os.path.isfile(RESULTS), f"File {RESULTS} does not exist. Did you save the output?"


def test_results_csv_line_count():
    with open(RESULTS, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 1000, f"Expected exactly 1000 lines in results.csv, but found {len(lines)}."


def test_no_nan_in_results():
    with open(RESULTS, 'r') as f:
        for i, line in enumerate(f, 1):
            assert "NaN" not in line and "nan" not in line.lower(), f"Line {i} contains NaN: {line.strip()}"


def test_data_783_stddev():
    found = False
    with open(RESULTS, 'r') as f:
        for line in f:
            if "data_783.txt" in line:
                found = True
                parts = line.strip().split(',')
                assert len(parts) == 2, f"Malformed line for data_783.txt: {line.strip()}"
                try:
                    stddev = float(parts[1])
                except ValueError:
                    assert False, f"Could not parse stddev as float for data_783.txt: {parts[1]}"
                assert math.isclose(stddev, 0.07483314773547883, rel_tol=1e-2), f"Incorrect stddev for data_783.txt. Expected ~0.074833, got {stddev}"
    assert found, "Output for data_783.txt not found in results.csv"


def test_data_402_stddev():
    found = False
    with open(RESULTS, 'r') as f:
        for line in f:
            if "data_402.txt" in line:
                found = True
                parts = line.strip().split(',')
                assert len(parts) == 2, f"Malformed line for data_402.txt: {line.strip()}"
                try:
                    stddev = float(parts[1])
                except ValueError:
                    assert False, f"Could not parse stddev as float for data_402.txt: {parts[1]}"
                assert math.isclose(stddev, 0.1, rel_tol=1e-2), f"Incorrect stddev for data_402.txt. Expected 0.1, got {stddev}"
    assert found, "Output for data_402.txt not found in results.csv"


def test_executable_exists():
    assert os.path.isfile(PROCESSOR), f"Executable {PROCESSOR} does not exist. Did you compile the code?"
    assert os.access(PROCESSOR, os.X_OK), f"File {PROCESSOR} is not executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROCESSOR} is not a compiled executable"


def test_all_results_are_complete_unique_and_correct():
    expected_names = {f"data_{i}.txt" for i in range(1000)}
    actual = {}
    with open(RESULTS, "r") as f:
        for line_number, raw in enumerate(f, 1):
            line = raw.strip()
            if not line:
                continue
            parts = line.rsplit(",", 1)
            assert len(parts) == 2, f"Malformed results.csv line {line_number}: {line!r}"
            name = os.path.basename(parts[0])
            assert name in expected_names, f"Unexpected filename on line {line_number}: {parts[0]!r}"
            assert name not in actual, f"Duplicate result for {name}"
            try:
                value = float(parts[1])
            except ValueError:
                assert False, f"Invalid stddev for {name}: {parts[1]!r}"
            assert math.isfinite(value), f"Non-finite stddev for {name}: {value}"
            actual[name] = value

    assert set(actual) == expected_names, "results.csv does not contain exactly one result for every input file"
    for name in sorted(expected_names):
        expected = expected_for_file(os.path.join(DATA_DIR, name))
        assert expected is not None
        assert math.isclose(actual[name], expected, rel_tol=2e-5, abs_tol=1e-7), (
            f"Incorrect stddev for {name}: expected {expected}, got {actual[name]}"
        )


def test_submitted_executable_on_all_input_files():
    for i in range(1000):
        path = os.path.join(DATA_DIR, f"data_{i}.txt")
        expected = expected_for_file(path)
        actual = parse_single_output(run_processor(PROCESSOR, path), path)
        assert math.isclose(actual, expected, rel_tol=2e-5, abs_tol=1e-7), (
            f"Executable produced incorrect output for {path}: expected {expected}, got {actual}"
        )


def test_executable_handles_unseen_malformed_and_unstable_data():
    assert_processor_behavior(PROCESSOR)


def test_modified_source_compiles_and_has_fixed_behavior():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist"
    with tempfile.TemporaryDirectory(prefix="source_build_") as td:
        rebuilt = os.path.join(td, "processor")
        completed = subprocess.run(
            ["g++", "-std=c++11", SOURCE, "-o", rebuilt],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, f"processor.cpp does not compile:\n{completed.stderr}"
        assert_processor_behavior(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
