#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

BINARY = "/home/user/classifier"
SOURCE = "/home/user/classifier.go"
TARGET = [10.0, 20.0, 30.0, 40.0, 50.0]
MAX_DISTANCE = 15.5
REJECT_TOKEN = "FATAL_ERR_99"


def test_classifier_binary_exists():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Classifier binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Classifier binary at {binary_path} is not executable"
    assert os.path.isfile(SOURCE), f"Go source not found at {SOURCE}"


def test_classifier_behavior():
    binary_path = BINARY
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failures = []
    for cf in clean_files:
        res = subprocess.run([binary_path, cf], capture_output=True)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        res = subprocess.run([binary_path, ef], capture_output=True)
        if res.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    err_msgs = []
    if evil_failures:
        err_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        err_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if err_msgs:
        pytest.fail(" | ".join(err_msgs))


@pytest.fixture(scope="session")
def rebuilt_binary():
    output = os.path.join(tempfile.mkdtemp(prefix="go-build-"), "program")
    result = subprocess.run(
        ["go", "build", "-o", output, SOURCE],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"classifier.go does not compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def expected_for_rows(rows):
    if any(REJECT_TOKEN in notes.strip() for _, _, notes in rows):
        return 1
    if len(rows) < 5:
        return 1
    values = [float(row[1]) for row in rows[:5]]
    distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(values, TARGET)))
    return 1 if distance > MAX_DISTANCE else 0


def expected_for_file(path):
    try:
        with open(path, "r", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            assert header == ["timestamp", "value", "notes"]
            rows = []
            for row in reader:
                assert len(row) == 3
                rows.append((row[0], row[1], row[2]))
        return expected_for_rows(rows)
    except (OSError, StopIteration, ValueError, csv.Error, AssertionError):
        return 1


def write_case(root, rows):
    path = os.path.join(root, uuid.uuid4().hex + ".csv")
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\r\n")
        writer.writerow(["timestamp", "value", "notes"])
        writer.writerows(rows)
    return path


def make_dynamic_cases(root):
    rng = secrets.SystemRandom()
    paths = []

    # Random clean vectors, with RFC 4180 quoting, commas, quotes, and newlines.
    safe_notes = ["ordinary", " two-sided whitespace ", "line one\nline two", 'comma, and "quote"']
    for _ in range(7):
        values = [base + rng.uniform(-4.0, 4.0) for base in TARGET]
        rows = [
            (str(i + 1), format(value, ".12g"), rng.choice(safe_notes))
            for i, value in enumerate(values)
        ]
        rows.append(("6", format(rng.uniform(-100, 100), ".12g"), "later row\nremains harmless"))
        paths.append(write_case(root, rows))

    # Random vectors whose independently computed distance exceeds the threshold.
    for _ in range(6):
        values = [base + rng.uniform(-1.0, 1.0) for base in TARGET]
        index = rng.randrange(5)
        values[index] += rng.choice([-1.0, 1.0]) * rng.uniform(18.0, 45.0)
        rows = [(str(i + 1), format(value, ".12g"), "ok") for i, value in enumerate(values)]
        paths.append(write_case(root, rows))

    # Place the reject token in quoted multiline notes, including after row five.
    for _ in range(5):
        count = rng.randint(6, 9)
        bad_index = rng.randrange(count)
        rows = []
        for i in range(count):
            value = TARGET[i] if i < 5 else rng.uniform(-500, 500)
            notes = "routine"
            if i == bad_index:
                notes = "  diagnostic line\n" + REJECT_TOKEN + " occurred\n  "
            rows.append((str(i + 1), format(value, ".12g"), notes))
        paths.append(write_case(root, rows))

    # Random files with too few rows.
    for _ in range(4):
        count = rng.randrange(0, 5)
        rows = [(str(i + 1), str(TARGET[i]), "ok") for i in range(count)]
        paths.append(write_case(root, rows))

    # Relocate the shipped fixtures to neutral, unpredictable paths as an explicit
    # guard against deciding from the clean/evil directory names.
    for directory in ("/app/corpus/clean", "/app/corpus/evil"):
        for name in os.listdir(directory):
            if name.endswith(".csv"):
                destination = os.path.join(root, uuid.uuid4().hex + ".csv")
                shutil.copyfile(os.path.join(directory, name), destination)
                paths.append(destination)

    return [(path, expected_for_file(path)) for path in paths]


def test_classifier_on_generated_neutral_paths(rebuilt_binary):
    with tempfile.TemporaryDirectory(prefix="inputs-") as root:
        cases = make_dynamic_cases(root)
        assert any(expected == 0 for _, expected in cases)
        assert any(expected == 1 for _, expected in cases)

        failures = []
        for executable in (BINARY, rebuilt_binary):
            for path, expected in cases:
                try:
                    result = subprocess.run([executable, path], capture_output=True, timeout=5)
                    actual = result.returncode
                except subprocess.TimeoutExpired:
                    actual = "timeout"
                if actual != expected:
                    failures.append(f"{os.path.basename(executable)} on {os.path.basename(path)}: expected {expected}, got {actual}")
        assert not failures, "Generated-case failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
