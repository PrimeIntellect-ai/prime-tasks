#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import shlex
import shutil
import subprocess
import tempfile

import pytest

HOME = "/home/user"
DATASET = os.path.join(HOME, "dataset.csv")
PROCESS = os.path.join(HOME, "process_data")
TRAIN = os.path.join(HOME, "train.csv")
TEST = os.path.join(HOME, "test.csv")


def read_dataset(path=DATASET):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["id", "value"], "Incorrect dataset header"
    assert len(rows) == 1001, f"Expected 1000 data rows, got {len(rows) - 1}"
    return [(row[0], float(row[1])) for row in rows[1:]]


def expected_rows(data):
    train_values = [value for _, value in data[:800]]
    mean = sum(train_values) / len(train_values)
    variance = sum((value - mean) ** 2 for value in train_values) / len(train_values)
    stddev = math.sqrt(variance)
    assert stddev > 0
    return [(record_id, (value - mean) / stddev) for record_id, value in data]


def validate_outputs(data):
    expected = expected_rows(data)
    for path, wanted in ((TRAIN, expected[:800]), (TEST, expected[800:])):
        assert os.path.isfile(path), f"Missing {path}"
        with open(path, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["id", "normalized_value"], f"Incorrect header in {path}"
        assert len(rows) == len(wanted) + 1, (
            f"Expected {len(wanted) + 1} lines in {path}, got {len(rows)}"
        )
        for index, (row, (expected_id, expected_value)) in enumerate(zip(rows[1:], wanted), 1):
            assert len(row) == 2, f"Malformed row {index} in {path}: {row}"
            assert row[0] == expected_id, (
                f"Incorrect id at row {index} in {path}: expected {expected_id}, got {row[0]}"
            )
            try:
                actual = float(row[1])
            except ValueError:
                pytest.fail(f"Non-numeric normalized value at row {index} in {path}: {row[1]}")
            assert math.isfinite(actual), f"Non-finite value at row {index} in {path}"
            assert math.isclose(actual, expected_value, rel_tol=1e-4, abs_tol=1e-6), (
                f"Incorrect normalized value at row {index} in {path}: "
                f"expected {expected_value}, got {actual}"
            )


def test_process_data_executable():
    assert os.path.isfile(PROCESS), f"Executable missing: {PROCESS}"
    assert os.access(PROCESS, os.X_OK), f"File is not executable: {PROCESS}"


def test_csv_outputs_exist_and_correct_length():
    assert os.path.isfile(TRAIN), f"Missing {TRAIN}"
    assert os.path.isfile(TEST), f"Missing {TEST}"

    with open(TRAIN, "r") as f:
        train_lines = f.readlines()
    with open(TEST, "r") as f:
        test_lines = f.readlines()

    assert len(train_lines) == 801, f"Expected 801 lines in train.csv, got {len(train_lines)}"
    assert len(test_lines) == 201, f"Expected 201 lines in test.csv, got {len(test_lines)}"
    assert train_lines[0].strip() == "id,normalized_value", "Incorrect header in train.csv"
    assert test_lines[0].strip() == "id,normalized_value", "Incorrect header in test.csv"


def test_data_leak_fixed():
    data = read_dataset()
    subprocess.run([PROCESS], cwd=HOME, check=True, timeout=30)
    validate_outputs(data)

    values = [i * 1.5 for i in range(1, 801)]
    mean = sum(values) / len(values)
    sq_sum = sum((v - mean) ** 2 for v in values)
    stddev = math.sqrt(sq_sum / len(values))
    expected_norm_801 = (1201.5 - mean) / stddev
    with open(TEST, "r") as f:
        test_lines = f.readlines()
    first_test_row = test_lines[1].strip()
    parts = first_test_row.split(",")
    assert len(parts) == 2, f"Malformed row in test.csv: {first_test_row}"
    assert parts[0] == "801", f"Expected first test id to be 801, got {parts[0]}"
    actual_norm = float(parts[1])
    assert math.isclose(actual_norm, expected_norm_801, rel_tol=1e-4), (
        f"Data leak not fixed. Expected normalized value ~{expected_norm_801}, got {actual_norm}"
    )


def test_process_data_on_derived_probe_input():
    with open(DATASET, "rb") as f:
        original = f.read()

    probe = []
    for i in range(1000):
        record_id = str(10001 + i)
        value = 17.0 + i * 0.37 + math.sin(i * 0.19) * 11.0 + ((i % 13) - 6) ** 2 * 0.07
        probe.append((record_id, value))

    try:
        with open(DATASET, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "value"])
            for record_id, value in probe:
                writer.writerow([record_id, format(value, ".17g")])
        subprocess.run([PROCESS], cwd=HOME, check=True, timeout=30)
        validate_outputs(probe)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original)
        subprocess.run([PROCESS], cwd=HOME, check=True, timeout=30)


def test_benchmark_script_and_log():
    script_path = os.path.join(HOME, "benchmark.sh")
    log_path = os.path.join(HOME, "benchmark_log.txt")

    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    assert os.path.isfile(log_path), f"Missing {log_path}"
    with open(log_path, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]
    assert len(log_lines) == 5, f"Expected exactly 5 lines in benchmark_log.txt, got {len(log_lines)}"
    for i, line in enumerate(log_lines):
        assert line == "Run complete", f"Line {i+1} in log is incorrect: {line}"

    temp_dir = tempfile.mkdtemp(prefix="benchmark_verify_")
    real_process = os.path.join(temp_dir, "real_process_data")
    counter = os.path.join(temp_dir, "invocations")
    shutil.move(PROCESS, real_process)
    try:
        with open(PROCESS, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf 'run\\n' >> " + shlex.quote(counter) + "\n")
            f.write("exec " + shlex.quote(real_process) + " \"$@\"\n")
        os.chmod(PROCESS, 0o755)
        with open(log_path, "w"):
            pass

        subprocess.run([script_path], cwd=HOME, check=True, timeout=60)

        with open(counter, "r") as f:
            invocations = f.readlines()
        assert len(invocations) == 5, (
            f"benchmark.sh must execute ./process_data exactly 5 times; got {len(invocations)}"
        )

        with open(log_path, "r") as f:
            fresh_log_lines = [line.strip() for line in f if line.strip()]
        assert len(fresh_log_lines) == 5, (
            f"Expected exactly 5 lines after running benchmark.sh, got {len(fresh_log_lines)}"
        )
        for i, line in enumerate(fresh_log_lines):
            assert line == "Run complete", f"Line {i+1} in log is incorrect: {line}"
    finally:
        if os.path.lexists(PROCESS):
            os.remove(PROCESS)
        shutil.move(real_process, PROCESS)
        shutil.rmtree(temp_dir, ignore_errors=True)

    validate_outputs(read_dataset())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
