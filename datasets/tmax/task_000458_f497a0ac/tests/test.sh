#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import time

import pytest

HOME = "/home/user"
CLEANER = os.path.join(HOME, "cleaner")
SOURCE = os.path.join(HOME, "cleaner.c")


def run_cleaner(executable, rows):
    work = tempfile.mkdtemp(prefix="cleaner-test-")
    try:
        data = os.path.join(work, "input.csv")
        with open(data, "w") as f:
            for row_id, value in rows:
                f.write(f"{row_id},{value:.12f}\n")

        subprocess.run([executable, data], cwd=work, check=True, timeout=10)
        train_path = os.path.join(work, "train_norm.csv")
        test_path = os.path.join(work, "test_norm.csv")
        assert os.path.isfile(train_path), "cleaner did not generate train_norm.csv"
        assert os.path.isfile(test_path), "cleaner did not generate test_norm.csv"

        def read_output(path):
            result = []
            with open(path) as f:
                lines = f.read().splitlines()
            for line in lines:
                assert re.fullmatch(r"-?\d+,-?\d+\.\d{4}", line), \
                    f"Output line is not an index and a value formatted to 4 decimals: {line!r}"
                row_id, value = line.split(",")
                result.append((int(row_id), float(value)))
            return result

        return read_output(train_path), read_output(test_path)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def assert_correct_normalization(executable):
    rng = random.SystemRandom()
    for count in (11, 17):
        ids = rng.sample(range(1000, 9999), count)
        values = [rng.uniform(-250.0, 350.0) + i * 0.371 for i in range(count)]
        rows = list(zip(ids, values))
        train_count = int(count * 0.8)
        train_values = values[:train_count]
        mean = sum(train_values) / train_count
        std = math.sqrt(sum((x - mean) ** 2 for x in train_values) / train_count)
        expected = [(ids[i], (values[i] - mean) / std) for i in range(count)]

        actual_train, actual_test = run_cleaner(executable, rows)
        actual = actual_train + actual_test
        assert len(actual_train) == train_count
        assert len(actual_test) == count - train_count
        assert len(actual) == count
        for (actual_id, actual_value), (expected_id, expected_value) in zip(actual, expected):
            assert actual_id == expected_id
            assert abs(actual_value - expected_value) <= 0.00011, \
                f"Incorrect normalization for id {expected_id}: got {actual_value}, expected {expected_value:.4f}"


@pytest.fixture(scope="session", autouse=True)
def generate_shipped_outputs():
    assert os.path.isfile(CLEANER), f"Executable {CLEANER} is missing."
    assert os.access(CLEANER, os.X_OK), f"File {CLEANER} is not executable."
    with open(CLEANER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cleaner must be a compiled executable"
    subprocess.run([CLEANER, os.path.join(HOME, "data.csv")], cwd=HOME, check=True, timeout=10)


def test_executable_exists():
    assert os.path.exists(CLEANER), f"Executable {CLEANER} is missing."
    assert os.access(CLEANER, os.X_OK), f"File {CLEANER} is not executable."


def test_normalized_csv_files_exist():
    assert os.path.exists(os.path.join(HOME, "train_norm.csv"))
    assert os.path.exists(os.path.join(HOME, "test_norm.csv"))


def test_test_norm_csv_contents():
    expected_content = "8,1.9640\n9,2.4004"
    with open(os.path.join(HOME, "test_norm.csv")) as f:
        content = f.read().strip()
    assert content == expected_content, f"Expected:\n{expected_content}\nGot:\n{content}"


def test_train_norm_csv_contents():
    expected_lines = [
        "0,-1.5275", "1,-1.0911", "2,-0.6547", "3,-0.2182",
        "4,0.2182", "5,0.6547", "6,1.0911", "7,1.5275"
    ]
    with open(os.path.join(HOME, "train_norm.csv")) as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 8
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected


def test_binary_and_corrected_source_on_unseen_data():
    assert_correct_normalization(CLEANER)
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing"
    work = tempfile.mkdtemp(prefix="source-build-")
    try:
        rebuilt = os.path.join(work, "cleaner")
        subprocess.run(["gcc", SOURCE, "-o", rebuilt, "-lm"], check=True, timeout=20)
        assert_correct_normalization(rebuilt)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_benchmark_script_exists_and_runs_twenty_timed_executions():
    benchmark = os.path.join(HOME, "benchmark.sh")
    avg_file = os.path.join(HOME, "benchmark_avg.txt")
    assert os.path.exists(benchmark), f"{benchmark} is missing."

    work = tempfile.mkdtemp(prefix="benchmark-check-")
    saved = os.path.join(work, "real_cleaner")
    counter = os.path.join(work, "count")
    lock = os.path.join(work, "lock")
    delays_path = os.path.join(work, "delays")
    rng = random.SystemRandom()
    delays = [rng.uniform(0.025, 0.115) for _ in range(20)]
    with open(counter, "w") as f:
        f.write("0\n")
    with open(delays_path, "w") as f:
        f.write("".join(f"{x:.6f}\n" for x in delays))

    os.replace(CLEANER, saved)
    wrapper = f'''#!/bin/bash
exec 9>"{lock}"
flock 9
n=$(cat "{counter}")
n=$((n + 1))
echo "$n" > "{counter}"
d=$(sed -n "${{n}}p" "{delays_path}")
flock -u 9
[ -n "$d" ] || exit 97
sleep "$d"
exec "{saved}" "$@"
'''
    try:
        with open(CLEANER, "w") as f:
            f.write(wrapper)
        os.chmod(CLEANER, 0o755)
        if os.path.exists(avg_file):
            os.unlink(avg_file)
        started = time.monotonic()
        subprocess.run(["bash", benchmark], cwd=HOME, check=True, timeout=30)
        elapsed = time.monotonic() - started

        with open(counter) as f:
            calls = int(f.read().strip())
        assert calls == 20, f"benchmark.sh ran cleaner {calls} times instead of 20"
        assert os.path.isfile(avg_file), f"{avg_file} is missing."
        text = open(avg_file).read().strip()
        assert text != "", f"{avg_file} is empty."
        try:
            average = float(text)
        except ValueError:
            pytest.fail(f"Contents of {avg_file} ({text!r}) cannot be parsed as a float.")
        assert math.isfinite(average) and average >= 0.0
        expected_average = sum(delays) / len(delays)
        assert abs(average - expected_average) <= 0.03, \
            f"Reported average {average} does not match the measured per-run timing"
        assert elapsed >= max(delays), "benchmark did not actually wait for cleaner runs"
    finally:
        if os.path.lexists(CLEANER):
            os.unlink(CLEANER)
        os.replace(saved, CLEANER)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
