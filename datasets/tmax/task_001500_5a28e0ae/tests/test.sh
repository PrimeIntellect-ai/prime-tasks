#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/cleaner"


def get_expected_details(filepath):
    records = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    # Deduplicate by sensor_id, keeping highest timestamp.
    latest = {}
    for record in records:
        sid = record["sensor_id"]
        if sid not in latest or record["timestamp"] > latest[sid]["timestamp"]:
            latest[sid] = record

    deduped = list(latest.values())
    if not deduped:
        return [], 0.0, 0.0, 0

    mean = sum(record["signal"] for record in deduped) / len(deduped)
    variance = sum((record["signal"] - mean) ** 2 for record in deduped) / len(deduped)
    stddev = math.sqrt(variance)

    surviving = []
    for record in deduped:
        if stddev == 0:
            surviving.append(record)
        else:
            z_score = abs((record["signal"] - mean) / stddev)
            if z_score <= 2.0:
                surviving.append(record)

    return surviving, mean, stddev, len(deduped) - len(surviving)


def get_expected_records(filepath):
    return get_expected_details(filepath)[0]


def run_cleaner(filepath):
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the Go program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    result = subprocess.run(
        [EXECUTABLE, filepath], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Cleaner failed on {filepath} with error:\n{result.stderr}"

    expected_records, mean, stddev, rejected = get_expected_details(filepath)
    expected_stderr = f"STATS: mean={mean:.2f} stddev={stddev:.2f} rejected={rejected}"
    assert result.stderr.strip() == expected_stderr, (
        f"Incorrect stderr for {filepath}. Expected {expected_stderr!r}, "
        f"got {result.stderr!r}"
    )

    output_records = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            try:
                output_records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON output from cleaner on {filepath}: {line}")

    return output_records


def assert_cleaner_result(filepath):
    expected = sorted(get_expected_records(filepath), key=lambda record: record["sensor_id"])
    actual = sorted(run_cleaner(filepath), key=lambda record: record["sensor_id"])
    assert actual == expected, f"Incorrect cleaned records for {filepath}"


def test_clean_corpus():
    clean_dir = "/app/corpus/clean"
    files = glob.glob(os.path.join(clean_dir, "*.jsonl"))
    assert files, f"No JSONL files found in {clean_dir}"

    failed_files = []
    for filepath in files:
        expected = get_expected_records(filepath)
        actual = run_cleaner(filepath)
        if sorted(expected, key=lambda x: x["sensor_id"]) != sorted(actual, key=lambda x: x["sensor_id"]):
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(files)} clean modified/rejected incorrectly. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus():
    evil_dir = "/app/corpus/evil"
    files = glob.glob(os.path.join(evil_dir, "*.jsonl"))
    assert files, f"No JSONL files found in {evil_dir}"

    failed_files = []
    for filepath in files:
        expected = get_expected_records(filepath)
        actual = run_cleaner(filepath)
        if sorted(expected, key=lambda x: x["sensor_id"]) != sorted(actual, key=lambda x: x["sensor_id"]):
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(files)} evil bypassed/handled incorrectly. "
            f"Offending files: {', '.join(failed_files)}"
        )


def write_jsonl(path, records):
    with open(path, "w") as output:
        for record in records:
            output.write(json.dumps(record, separators=(",", ":")) + "\n")


def test_newly_generated_inputs():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)

    with tempfile.TemporaryDirectory(prefix="cleaner_hidden_") as directory:
        datasets = []

        # A point whose population z-score is exactly 2.0 must survive because
        # rejection is strictly greater than 2.0.
        boundary = [
            {"sensor_id": f"{token}_boundary_{i}", "timestamp": 100 + i, "signal": value}
            for i, value in enumerate([0, 0, 0, 0, 10])
        ]
        datasets.append(boundary)

        # Zero standard deviation and duplicate handling.
        zero_std = [
            {"sensor_id": f"{token}_flat_{i}", "timestamp": 500 + i, "signal": 7}
            for i in range(7)
        ]
        zero_std.extend([
            {"sensor_id": f"{token}_flat_1", "timestamp": 1, "signal": -8000},
            {"sensor_id": f"{token}_flat_4", "timestamp": 2, "signal": 9000},
        ])
        datasets.append(zero_std)

        # Random, previously unseen values, names, ordering, duplicates, and
        # outliers that are not the corpus's obvious signal=10000.0 records.
        for case in range(5):
            records = []
            count = rng.randint(11, 27)
            for i in range(count):
                sid = f"{token}_{case}_{secrets.token_hex(4)}_{i}"
                timestamp = rng.randint(10000, 90000)
                signal = rng.randint(-35, 65)
                records.append({"sensor_id": sid, "timestamp": timestamp, "signal": signal})

                if rng.random() < 0.55:
                    records.append({
                        "sensor_id": sid,
                        "timestamp": timestamp - rng.randint(1, 5000),
                        "signal": rng.choice([-731, 844, 1297]),
                    })

            # One extreme among enough ordinary points has |z| > 2.
            records.append({
                "sensor_id": f"{token}_{case}_high",
                "timestamp": 95000,
                "signal": rng.choice([417, 563, 911]),
            })
            if case % 2:
                records.append({
                    "sensor_id": f"{token}_{case}_low",
                    "timestamp": 96000,
                    "signal": rng.choice([-509, -677, -823]),
                })
            rng.shuffle(records)
            datasets.append(records)

        for index, records in enumerate(datasets):
            path = os.path.join(directory, f"{secrets.token_hex(10)}_{index}.jsonl")
            write_jsonl(path, records)
            assert_cleaner_result(path)


def test_exactly_one_argument_cli():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with tempfile.TemporaryDirectory(prefix="cleaner_cli_") as directory:
        path = os.path.join(directory, f"{secrets.token_hex(8)}.jsonl")
        write_jsonl(path, [{"sensor_id": "cli", "timestamp": 1, "signal": 3}])

        no_args = subprocess.run([EXECUTABLE], capture_output=True, text=True, timeout=10)
        assert no_args.returncode != 0, "Cleaner must reject invocation with no file argument"

        two_args = subprocess.run(
            [EXECUTABLE, path, path], capture_output=True, text=True, timeout=10
        )
        assert two_args.returncode != 0, "Cleaner must reject invocation with more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
