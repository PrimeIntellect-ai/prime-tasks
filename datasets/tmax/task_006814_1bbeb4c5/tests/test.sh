#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

EXPECTED_KEYS = {"bucket", "server_id", "avg_cpu", "max_mem_norm", "spike_count"}
INPUT_FILE = "/home/user/raw_metrics.csv"
OUTPUT_FILE = "/home/user/etl_output.jsonl"


def compute_expected_output(input_file):
    groups = {}
    with open(input_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row:
                continue
            timestamp = int(row["timestamp"])
            server_id = row["server_id"]
            cpu_usage = float(row["cpu_usage"])
            memory_bytes = int(row["memory_bytes"])

            bucket = timestamp - (timestamp % 300)
            key = (bucket, server_id)

            if key not in groups:
                groups[key] = {
                    "cpu_usages": [],
                    "max_memory": -1,
                    "spike_count": 0,
                }

            groups[key]["cpu_usages"].append(cpu_usage)
            if memory_bytes > groups[key]["max_memory"]:
                groups[key]["max_memory"] = memory_bytes
            if cpu_usage > 90.0:
                groups[key]["spike_count"] += 1

    expected_output = []
    for key in sorted(groups.keys()):
        bucket, server_id = key
        data = groups[key]
        avg_cpu = sum(data["cpu_usages"]) / len(data["cpu_usages"])
        max_mem_norm = data["max_memory"] / 32000000000.0
        expected_output.append({
            "bucket": bucket,
            "server_id": server_id,
            "avg_cpu": avg_cpu,
            "max_mem_norm": max_mem_norm,
            "spike_count": data["spike_count"],
        })
    return expected_output


def read_output(output_file):
    assert os.path.exists(output_file), f"Output file {output_file} does not exist. Did you run your ETL pipeline?"
    assert os.path.isfile(output_file), f"{output_file} is not a valid file."

    actual_data = []
    with open(output_file, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_file} is not a valid JSON object.")
            assert isinstance(record, dict), f"Line {line_num} is not a JSON object."
            actual_data.append(record)
    return actual_data


def assert_correct_output(input_file, output_file):
    expected_data = compute_expected_output(input_file)
    actual_data = read_output(output_file)

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert set(actual.keys()) == EXPECTED_KEYS, (
            f"Record {i} must have exactly the keys {sorted(EXPECTED_KEYS)}, "
            f"but has {sorted(actual.keys())}."
        )
        assert type(actual["bucket"]) is int, f"Record {i} bucket must be an integer."
        assert type(actual["server_id"]) is str, f"Record {i} server_id must be a string."
        assert type(actual["avg_cpu"]) is float, f"Record {i} avg_cpu must be a float."
        assert type(actual["max_mem_norm"]) is float, f"Record {i} max_mem_norm must be a float."
        assert type(actual["spike_count"]) is int, f"Record {i} spike_count must be an integer."

        assert actual["bucket"] == expected["bucket"], f"Record {i} bucket mismatch: expected {expected['bucket']}, got {actual['bucket']}."
        assert actual["server_id"] == expected["server_id"], f"Record {i} server_id mismatch: expected {expected['server_id']}, got {actual['server_id']}."
        assert actual["spike_count"] == expected["spike_count"], f"Record {i} spike_count mismatch: expected {expected['spike_count']}, got {actual['spike_count']}."
        assert math.isclose(actual["avg_cpu"], expected["avg_cpu"], rel_tol=1e-4, abs_tol=1e-4), f"Record {i} avg_cpu mismatch: expected {expected['avg_cpu']}, got {actual['avg_cpu']}."
        assert math.isclose(actual["max_mem_norm"], expected["max_mem_norm"], rel_tol=1e-4, abs_tol=1e-4), f"Record {i} max_mem_norm mismatch: expected {expected['max_mem_norm']}, got {actual['max_mem_norm']}."


def rust_candidates():
    cargo_projects = []
    standalone_sources = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"target", ".git", ".cargo"}]
        root_path = Path(root)
        if "Cargo.toml" in files and (root_path / "src" / "main.rs").is_file():
            cargo_projects.append(root_path / "Cargo.toml")
        for name in files:
            if name.endswith(".rs"):
                standalone_sources.append(root_path / name)
    return sorted(cargo_projects), sorted(standalone_sources)


def run_command(command, cwd, env):
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def candidate_produces_correct_output(command, cwd, env):
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    if not run_command(command, cwd, env):
        return False
    try:
        assert_correct_output(INPUT_FILE, OUTPUT_FILE)
        return True
    except (AssertionError, OSError, ValueError, TypeError):
        return False


def test_etl_output_exists_and_correct():
    assert_correct_output(INPUT_FILE, OUTPUT_FILE)


def test_rust_program_executes_on_derived_input():
    cargo_projects, standalone_sources = rust_candidates()
    assert cargo_projects or standalone_sources, "No Rust program source was found under /home/user."

    original_input = Path(INPUT_FILE).read_bytes()
    original_output = Path(OUTPUT_FILE).read_bytes() if Path(OUTPUT_FILE).is_file() else None
    token = secrets.token_hex(4)
    base = (1800000000 + secrets.randbelow(100000) * 300)
    server_a = f"a_{token}"
    server_z = f"z_{token}"
    rows = [
        [base + 299, server_z, "90.0", "31999999999"],
        [base + 2, server_a, "10.25", "1000000000"],
        [base + 1, server_a, "90.0001", "12345678901"],
        [base + 300, server_z, "99.75", "16000000000"],
        [base + 450, server_z, "40.5", "24000000000"],
        [base + 601, server_a, "91.125", "32000000000"],
        [base + 620, server_a, "12.375", "8000000000"],
    ]

    env = os.environ.copy()
    env["PATH"] = "/usr/local/bin:/opt/rust/bin:" + env.get("PATH", "")
    env["RUSTUP_HOME"] = "/opt/rust"
    env["CARGO_HOME"] = "/opt/rust"

    try:
        with open(INPUT_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "server_id", "cpu_usage", "memory_bytes"])
            writer.writerows(rows)

        for manifest in cargo_projects:
            if candidate_produces_correct_output(
                ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                manifest.parent,
                env,
            ):
                return

        with tempfile.TemporaryDirectory(prefix="rust_verify_") as temp_dir:
            for source in standalone_sources:
                binary = Path(temp_dir) / ("candidate_" + secrets.token_hex(6))
                if not run_command(["rustc", str(source), "-o", str(binary)], source.parent, env):
                    continue
                if candidate_produces_correct_output([str(binary)], source.parent, env):
                    return

        pytest.fail("No submitted Rust program could be executed to correctly process a verifier-derived CSV input.")
    finally:
        Path(INPUT_FILE).write_bytes(original_input)
        if original_output is None:
            if Path(OUTPUT_FILE).exists():
                Path(OUTPUT_FILE).unlink()
        else:
            Path(OUTPUT_FILE).write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
