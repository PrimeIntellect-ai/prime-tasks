#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import json
import math
import os
import stat
import subprocess

RAW = "/home/user/raw_data/sensors_20231001.csv"
BASELINE = "/home/user/reference/baseline.json"
CLEAN = "/home/user/clean_data/sensors_20231001_clean.csv"
DISTANCES = "/home/user/metrics/distances.csv"
DEDUP = "/home/user/dedup.py"
METRICS = "/home/user/compute_metrics.py"
PIPELINE = "/home/user/run_pipeline.sh"


def run_as_user(command):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        capture_output=True,
        text=True,
    )


def remove_outputs():
    for path in (CLEAN, DISTANCES):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def expected_clean_rows(raw_path):
    with open(raw_path, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["timestamp", "sensor_id", "value"], "Raw CSV has an unexpected header."
        seen = set()
        rows = []
        for row in reader:
            assert len(row) == 3, f"Malformed raw row: {row}"
            digest = hashlib.md5(",".join(row).encode()).hexdigest()
            if digest not in seen:
                seen.add(digest)
                rows.append(row)
    return sorted(rows, key=lambda row: (row[1], row[0]))


def expected_distance_rows(raw_path, baseline_path):
    clean_rows = expected_clean_rows(raw_path)
    with open(baseline_path) as f:
        baseline = json.load(f)
    assert len(baseline) == 24

    grouped = {}
    for timestamp, sensor_id, value in clean_rows:
        grouped.setdefault(sensor_id, []).append(float(value))

    result = []
    for sensor_id in sorted(grouped):
        values = grouped[sensor_id]
        assert len(values) == 24, f"Sensor {sensor_id} does not have exactly 24 readings."
        distance = math.sqrt(sum((value - base) ** 2 for value, base in zip(values, baseline)))
        result.append([sensor_id, f"{distance:.2f}"])
    return result


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def validate_outputs(raw_path, baseline_path):
    assert os.path.isfile(CLEAN), f"Clean data file missing: {CLEAN}"
    clean_data = read_csv(CLEAN)
    assert clean_data and clean_data[0] == ["timestamp", "sensor_id", "value"], "Clean data file has incorrect header."
    assert clean_data[1:] == expected_clean_rows(raw_path), "Clean data does not match MD5 first-occurrence deduplication of the raw CSV."

    assert os.path.isfile(DISTANCES), f"Distances file missing: {DISTANCES}"
    distance_data = read_csv(DISTANCES)
    assert distance_data and distance_data[0] == ["sensor_id", "distance"], "Distances file has incorrect header."
    assert distance_data[1:] == expected_distance_rows(raw_path, baseline_path), "Distances are not the expected values derived from the raw data and baseline."


def assert_md5_implementation(path):
    with open(path) as f:
        tree = ast.parse(f.read(), filename=path)

    hashlib_names = set()
    md5_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "hashlib":
                    hashlib_names.add(alias.asname or "hashlib")
        elif isinstance(node, ast.ImportFrom) and node.module == "hashlib":
            for alias in node.names:
                if alias.name == "md5":
                    md5_names.add(alias.asname or "md5")

    found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in md5_names:
            found = True
        if (isinstance(node.func, ast.Attribute) and node.func.attr == "md5"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in hashlib_names):
            found = True
    assert found, "dedup.py must compute MD5 hashes using hashlib.md5."


def test_01_scripts_and_pipeline_behavior():
    for path in (DEDUP, METRICS, PIPELINE):
        assert os.path.isfile(path), f"Required script missing: {path}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required script is not a regular file: {path}"
    assert os.access(PIPELINE, os.X_OK), "run_pipeline.sh is not executable."
    assert_md5_implementation(DEDUP)

    saved = {}
    for path in (RAW, BASELINE, DEDUP, METRICS):
        with open(path, "rb") as f:
            saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))

    marker = "/tmp/compute_metrics_was_called"
    recovery = None
    try:
        baseline = [3.25 + i * 0.75 for i in range(24)]
        with open(BASELINE, "w") as f:
            json.dump(baseline, f)

        rows = []
        for sensor_id, offset in (("sensor_Z", 2.5), ("sensor_M", -1.25), ("sensor_A", 0.125)):
            for hour in range(23, -1, -1):
                row = [f"2024-02-03T{hour:02d}:00:00Z", sensor_id, f"{baseline[hour] + offset + (hour % 4) / 10:.4f}"]
                rows.append(row)
                if hour in (1, 7, 19):
                    rows.append(list(row))
        rows = rows[17:] + rows[:17]
        with open(RAW, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "sensor_id", "value"])
            writer.writerows(rows)

        remove_outputs()
        result = run_as_user(["python3", DEDUP])
        assert result.returncode == 0, f"dedup.py failed on test input:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(CLEAN), "dedup.py did not create the clean CSV."
        assert read_csv(CLEAN)[1:] == expected_clean_rows(RAW), "dedup.py produced incorrect data on an independent input."

        try:
            os.unlink(DISTANCES)
        except FileNotFoundError:
            pass
        result = run_as_user(["python3", METRICS])
        assert result.returncode == 0, f"compute_metrics.py failed on test input:\n{result.stdout}\n{result.stderr}"
        validate_outputs(RAW, BASELINE)

        remove_outputs()
        result = run_as_user([PIPELINE])
        assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
        validate_outputs(RAW, BASELINE)

        with open(DEDUP, "w") as f:
            f.write("#!/usr/bin/env python3\nimport sys\nsys.exit(37)\n")
        os.chmod(DEDUP, 0o755)
        with open(METRICS, "w") as f:
            f.write("#!/usr/bin/env python3\nfrom pathlib import Path\nPath(%r).write_text('called')\n" % marker)
        os.chmod(METRICS, 0o755)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

        result = run_as_user([PIPELINE])
        assert result.returncode != 0, "run_pipeline.sh did not propagate a deduplication failure."
        assert not os.path.exists(marker), "run_pipeline.sh executed compute_metrics.py after dedup.py failed."
    finally:
        for path, (content, mode) in saved.items():
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
        remove_outputs()
        recovery = run_as_user([PIPELINE])

    assert recovery.returncode == 0, f"Pipeline failed on the supplied data:\n{recovery.stdout}\n{recovery.stderr}"


def test_clean_data_csv():
    assert os.path.isfile(CLEAN), f"Clean data file missing: {CLEAN}"

    with open(CLEAN, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["timestamp", "sensor_id", "value"], "Clean data file has incorrect header."
        rows = list(reader)
        assert len(rows) == 72, f"Expected 72 data rows, got {len(rows)}."

        for i in range(len(rows) - 1):
            assert (rows[i][1], rows[i][0]) <= (rows[i + 1][1], rows[i + 1][0]), "Clean data is not properly sorted by sensor_id, then timestamp."

        seen = set()
        for row in rows:
            record = (row[0], row[1], row[2])
            assert record not in seen, f"Duplicate record found: {record}"
            seen.add(record)

    assert rows == expected_clean_rows(RAW), "Clean CSV does not contain the correct first-occurrence MD5 deduplication of the supplied raw CSV."


def test_distances_csv():
    assert os.path.isfile(DISTANCES), f"Distances file missing: {DISTANCES}"

    expected_rows = expected_distance_rows(RAW, BASELINE)
    expected_distances = dict(expected_rows)

    with open(DISTANCES, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["sensor_id", "distance"], "Distances file has incorrect header."
        rows = list(reader)
        assert len(rows) == len(expected_distances), f"Expected {len(expected_distances)} distance rows, got {len(rows)}."

        for i in range(len(rows) - 1):
            assert rows[i][0] <= rows[i + 1][0], "Distances file is not sorted by sensor_id."

        for row in rows:
            sensor_id, dist = row
            assert sensor_id in expected_distances, f"Unexpected sensor_id: {sensor_id}"
            assert dist == expected_distances[sensor_id], f"Incorrect distance for {sensor_id}: expected {expected_distances[sensor_id]}, got {dist}"

    assert rows == expected_rows, "Distances CSV does not exactly match values derived from the raw CSV and baseline."


def test_cron_job():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to list crontab."

    crontab_content = result.stdout
    assert "run_pipeline.sh" in crontab_content, "run_pipeline.sh not found in crontab."

    found = False
    for line in crontab_content.splitlines():
        if "run_pipeline.sh" in line and not line.strip().startswith("#"):
            parts = line.split()
            if len(parts) >= 5 and parts[:5] == ["0", "0", "*", "*", "*"]:
                found = True
                assert parts[5:] == [PIPELINE], "Cron job must simply execute /home/user/run_pipeline.sh."
                break
    assert found, "Cron job for run_pipeline.sh is not scheduled at exactly '0 0 * * *'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
