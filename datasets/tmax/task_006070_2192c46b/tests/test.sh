#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess

SOURCE = "/home/user/processor.cpp"
EXECUTABLE = "/home/user/sensor_processor"
INPUT = "/home/user/sensor_data.csv"
OUTPUT = "/home/user/processed_stats.csv"
LOG = "/home/user/pipeline.log"
HEADER = "bucket_start,mean,max,min,is_anomaly"


def compute_expected(input_file):
    buckets = {}
    valid_records = 0
    with open(input_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) >= 3:
                try:
                    ts = int(parts[0])
                    temp = float(parts[2])
                    bucket = (ts // 60) * 60
                    buckets.setdefault(bucket, []).append(temp)
                    valid_records += 1
                except ValueError:
                    pass

    expected_stats = []
    prev_mean = None
    anomalies = 0
    for bucket in sorted(buckets):
        temps = buckets[bucket]
        mean_val = sum(temps) / len(temps)
        is_anomaly = 0
        if prev_mean is not None and abs(mean_val - prev_mean) > 5.0:
            is_anomaly = 1
            anomalies += 1
        expected_stats.append({
            "bucket_start": str(bucket),
            "mean": f"{mean_val:.1f}",
            "max": f"{max(temps):.1f}",
            "min": f"{min(temps):.1f}",
            "is_anomaly": str(is_anomaly),
        })
        prev_mean = mean_val
    return expected_stats, valid_records, anomalies


def assert_outputs_match(input_file):
    expected_stats, valid_records, anomalies = compute_expected(input_file)

    assert os.path.exists(OUTPUT), f"{OUTPUT} does not exist."
    with open(OUTPUT, "r", newline="") as f:
        first_line = f.readline().rstrip("\r\n")
        assert first_line == HEADER, f"Expected exact CSV header {HEADER!r}, got {first_line!r}."
        f.seek(0)
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER.split(","), f"Unexpected CSV columns: {reader.fieldnames}."
        actual_stats = list(reader)

    assert len(actual_stats) == len(expected_stats), \
        f"Expected {len(expected_stats)} rows in output, got {len(actual_stats)}."
    for actual, expected in zip(actual_stats, expected_stats):
        assert actual.get("bucket_start") == expected["bucket_start"], \
            f"Expected bucket_start {expected['bucket_start']}, got {actual.get('bucket_start')}."
        assert actual.get("mean") == expected["mean"], \
            f"Bucket {expected['bucket_start']}: Expected mean {expected['mean']}, got {actual.get('mean')}."
        assert actual.get("max") == expected["max"], \
            f"Bucket {expected['bucket_start']}: Expected max {expected['max']}, got {actual.get('max')}."
        assert actual.get("min") == expected["min"], \
            f"Bucket {expected['bucket_start']}: Expected min {expected['min']}, got {actual.get('min')}."
        assert actual.get("is_anomaly") == expected["is_anomaly"], \
            f"Bucket {expected['bucket_start']}: Expected is_anomaly {expected['is_anomaly']}, got {actual.get('is_anomaly')}."

    assert os.path.exists(LOG), f"{LOG} does not exist."
    with open(LOG, "r") as f:
        log_lines = f.read().splitlines()
    expected_lines = [
        "[INFO] Pipeline started",
        f"[INFO] Processed {valid_records} valid records",
        f"[WARN] Detected {anomalies} anomalies",
        "[INFO] Pipeline completed",
    ]
    assert log_lines == expected_lines, \
        f"Expected log to contain exactly {expected_lines!r}, got {log_lines!r}."


def test_files_exist():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."
    assert os.path.exists(EXECUTABLE), f"{EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_existing_csv_and_logs_computed_from_input():
    assert os.path.exists(INPUT), f"{INPUT} does not exist."
    assert_outputs_match(INPUT)


def test_program_and_source_implement_pipeline():
    paths = [INPUT, OUTPUT, LOG]
    snapshots = {}
    for path in paths:
        snapshots[path] = open(path, "rb").read() if os.path.exists(path) else None

    rebuilt = "/tmp/sensor_processor_from_source"
    try:
        subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        rng = random.SystemRandom()
        base = rng.randrange(20000000, 30000000) * 60
        first_mean = rng.randint(-20, 40)
        means = [first_mean, first_mean + 5, first_mean + 11, first_mean + 4]
        bucket_offsets = [0, 1, 3, 7]
        records = []
        for index, (offset, mean) in enumerate(zip(bucket_offsets, means)):
            bucket = base + offset * 60
            records.extend([
                f"{bucket},S{index}A,{mean - 2}.0",
                f"{bucket + 17},S{index}B,{mean}.0",
                f"{bucket + 59},S{index}C,{mean + 2}.0",
            ])
        rng.shuffle(records)
        challenge = "\n".join(records) + "\n"

        for program in (EXECUTABLE, rebuilt):
            with open(INPUT, "w") as f:
                f.write(challenge)
            for generated in (OUTPUT, LOG):
                if os.path.exists(generated):
                    os.remove(generated)
            subprocess.run(
                [program],
                check=True,
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert_outputs_match(INPUT)
    finally:
        for path, content in snapshots.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
