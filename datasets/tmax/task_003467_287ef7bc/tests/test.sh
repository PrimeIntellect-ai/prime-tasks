#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -f /home/user/output/regional_load.csv
initial_run_ok=0
if timeout 300s /home/user/run_etl.sh; then
    initial_run_ok=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid
from collections import defaultdict

import pytest


def test_run_etl_script_exists_and_executable():
    script_path = "/home/user/run_etl.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_rust_project_exists():
    project = "/home/user/etl_pipeline"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isdir(project), f"Rust project {project} does not exist."
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} does not exist."
    rust_sources = glob.glob(os.path.join(project, "**", "*.rs"), recursive=True)
    assert rust_sources, "The Rust project contains no .rs source files."


def test_output_csv_exists_and_correct():
    output_path = "/home/user/output/regional_load.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r", newline="") as f:
        content = f.read().strip().replace("\r\n", "\n")

    expected_content = (
        "region_id,hour,sum_z_score\n"
        "Region_A,2023-10-01T10:00:00Z,-2.0000\n"
        "Region_A,2023-10-01T11:00:00Z,2.0000\n"
        "Region_B,2023-10-01T10:00:00Z,-1.0000\n"
        "Region_B,2023-10-01T11:00:00Z,1.0000"
    )

    assert content == expected_content, f"Content of {output_path} does not match the expected output. Got:\n{content}"


def test_output_csv_parsed_values():
    output_path = "/home/user/output/regional_load.csv"
    if not os.path.isfile(output_path):
        pytest.fail(f"Output file {output_path} does not exist.")

    with open(output_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output CSV is empty."
    assert rows[0] == ["region_id", "hour", "sum_z_score"], "CSV headers are incorrect."

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected 4 data rows, got {len(data_rows)}."

    regions = [row[0] for row in data_rows]
    hours = [row[1] for row in data_rows]

    assert regions == sorted(regions), "Rows are not sorted alphabetically by region_id."

    expected_data = [
        ["Region_A", "2023-10-01T10:00:00Z", "-2.0000"],
        ["Region_A", "2023-10-01T11:00:00Z", "2.0000"],
        ["Region_B", "2023-10-01T10:00:00Z", "-1.0000"],
        ["Region_B", "2023-10-01T11:00:00Z", "1.0000"],
    ]

    for i, (expected, actual) in enumerate(zip(expected_data, data_rows)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected region {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: Expected hour {expected[1]}, got {actual[1]}"

        try:
            actual_val = float(actual[2])
            expected_val = float(expected[2])
            assert abs(actual_val - expected_val) < 1e-4, f"Row {i+1}: Expected sum_z_score {expected_val}, got {actual_val}"

            decimal_part = actual[2].split('.')[-1] if '.' in actual[2] else ""
            assert len(decimal_part) == 4, f"Row {i+1}: sum_z_score must be formatted to 4 decimal places, got '{actual[2]}'"
        except ValueError:
            pytest.fail(f"Row {i+1}: sum_z_score '{actual[2]}' is not a valid float.")


def build_and_find_binary():
    manifest = "/home/user/etl_pipeline/Cargo.toml"
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd="/home/user/etl_pipeline",
        text=True,
        capture_output=True,
        timeout=120,
        check=True,
    )
    metadata = json.loads(metadata_result.stdout)
    root_id = (metadata.get("resolve") or {}).get("root")
    packages = metadata["packages"]
    package = next((p for p in packages if p["id"] == root_id), None)
    if package is None:
        defaults = metadata.get("workspace_default_members", [])
        package = next((p for p in packages if p["id"] in defaults), None)
    if package is None:
        package = next((p for p in packages if p["id"] in metadata.get("workspace_members", [])), None)
    assert package is not None, "Cargo metadata contains no buildable package."

    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Rust project has no binary target."
    default_run = package.get("default_run")
    target = next((t for t in bins if t["name"] == default_run), None)
    if target is None and len(bins) == 1:
        target = bins[0]
    if target is None:
        target = next((t for t in bins if t["name"] == package["name"]), bins[0])

    command = [
        "cargo", "build", "--release", "--message-format=json",
        "--manifest-path", manifest, "--package", package["name"], "--bin", target["name"],
    ]
    result = subprocess.run(
        command,
        cwd="/home/user/etl_pipeline",
        text=True,
        capture_output=True,
        timeout=300,
        check=True,
    )
    executable = None
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (message.get("reason") == "compiler-artifact"
                and message.get("target", {}).get("name") == target["name"]
                and message.get("executable")):
            executable = message["executable"]
    assert executable and os.path.isfile(executable), "Cargo did not produce the requested release binary."
    return executable


def compute_expected(metadata, records):
    dedup = {}
    for record in records:
        key = (record["meter_id"], record["timestamp"])
        if key not in dedup or record["reading_kw"] > dedup[key]["reading_kw"]:
            dedup[key] = record

    by_meter = defaultdict(list)
    for record in dedup.values():
        if record["meter_id"] in metadata:
            by_meter[record["meter_id"]].append(record)

    aggregate = defaultdict(float)
    for meter, meter_records in by_meter.items():
        values = [float(r["reading_kw"]) for r in meter_records]
        mean = sum(values) / len(values)
        variance = sum((value - mean) ** 2 for value in values) / len(values)
        sigma = math.sqrt(variance)
        for record, value in zip(meter_records, values):
            z = 0.0 if len(values) == 1 or sigma == 0.0 else (value - mean) / sigma
            hour = record["timestamp"][:13] + ":00:00Z"
            aggregate[(metadata[meter], hour)] += z
    return sorted(aggregate.items())


def test_compiled_rust_binary_on_generated_inputs():
    data_dir = "/home/user/data"
    output_path = "/home/user/output/regional_load.csv"
    original_paths = set(glob.glob(os.path.join(data_dir, "readings_*.jsonl")))
    original_paths.add(os.path.join(data_dir, "metadata.csv"))
    backups = {path: open(path, "rb").read() for path in original_paths if os.path.exists(path)}

    rng = random.SystemRandom()
    suffix = uuid.uuid4().hex[:8]
    regions = [f"Area_{rng.randrange(1000, 9999)}_{suffix}" for _ in range(3)]
    regions = list(dict.fromkeys(regions))
    while len(regions) < 3:
        regions.append(f"Area_{rng.randrange(1000, 9999)}_{uuid.uuid4().hex[:8]}")
    meters = [f"T{i}_{suffix}" for i in range(6)]
    metadata = {
        meters[0]: regions[0], meters[1]: regions[1], meters[2]: regions[2],
        meters[3]: rng.choice(regions), meters[4]: rng.choice(regions), meters[5]: rng.choice(regions),
    }

    records = []
    for i, meter in enumerate(meters):
        count = 1 if i == 0 else (3 if i == 1 else rng.randint(3, 6))
        constant = round(rng.uniform(20.0, 80.0), 3)
        for j in range(count):
            day = 2 + ((i + j) % 3)
            hour = (3 * i + 2 * j + rng.randrange(0, 2)) % 24
            minute = (7 * i + 11 * j) % 60
            second = (13 * i + 17 * j) % 60
            timestamp = f"2024-02-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"
            value = constant if i == 1 else round(rng.uniform(-25.0, 240.0), 3)
            records.append({"timestamp": timestamp, "meter_id": meter, "reading_kw": value})
            if j == 0 and i >= 2:
                records.append({"timestamp": timestamp, "meter_id": meter, "reading_kw": value - rng.uniform(1.0, 20.0)})
                records.append({"timestamp": timestamp, "meter_id": meter, "reading_kw": value + rng.uniform(0.5, 9.0)})

    records.append({
        "timestamp": "2024-02-02T09:19:29Z",
        "meter_id": "UNKNOWN_" + suffix,
        "reading_kw": rng.uniform(500.0, 900.0),
    })
    rng.shuffle(records)
    expected = compute_expected(metadata, records)

    try:
        for path in glob.glob(os.path.join(data_dir, "readings_*.jsonl")):
            os.remove(path)
        with open(os.path.join(data_dir, "metadata.csv"), "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["meter_id", "region_id"])
            for meter, region in metadata.items():
                writer.writerow([meter, region])
        chunks = [records[i::3] for i in range(3)]
        for index, chunk in enumerate(chunks, 1):
            with open(os.path.join(data_dir, f"readings_{index}.jsonl"), "w") as f:
                for record in chunk:
                    f.write(json.dumps(record) + "\n")

        if os.path.exists(output_path):
            os.remove(output_path)
        executable = build_and_find_binary()
        subprocess.run([executable], cwd="/home/user/etl_pipeline", timeout=120, check=True)
        assert os.path.isfile(output_path), "The compiled Rust program did not create regional_load.csv."

        with open(output_path, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["region_id", "hour", "sum_z_score"], "CSV headers are incorrect."
        actual_rows = rows[1:]
        assert len(actual_rows) == len(expected), f"Expected {len(expected)} generated output rows, got {len(actual_rows)}."

        actual_keys = [(row[0], row[1]) for row in actual_rows]
        expected_keys = [key for key, value in expected]
        assert actual_keys == expected_keys, "Generated output is missing buckets or is not sorted by region and hour."
        assert len(set(actual_keys)) == len(actual_keys), "Generated output contains duplicate region-hour buckets."
        for row, (_, expected_value) in zip(actual_rows, expected):
            assert len(row) == 3, f"Malformed output row: {row}"
            assert re.fullmatch(r"-?\d+\.\d{4}", row[2]), f"sum_z_score is not formatted to four decimal places: {row[2]}"
            actual_value = float(row[2])
            assert math.isfinite(actual_value), "sum_z_score must be finite."
            assert abs(actual_value - expected_value) <= 0.000051, (
                f"Wrong aggregate for {(row[0], row[1])}: expected {expected_value}, got {actual_value}"
            )
    finally:
        for path in glob.glob(os.path.join(data_dir, "readings_*.jsonl")):
            os.remove(path)
        metadata_path = os.path.join(data_dir, "metadata.csv")
        if os.path.exists(metadata_path):
            os.remove(metadata_path)
        for path, content in backups.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(content)
TEST_EOF

if [ "$initial_run_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
