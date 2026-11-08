#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import shutil
import subprocess

import pytest

PROJECT = "/home/user/drift_analyzer"
DATA_DIR = "/home/user/drift_data"
JSON_PATH = "/home/user/alerts.json"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
PROBE_NAME = "verifier_probe_" + secrets.token_hex(8)
PROBE_PATH = os.path.join(DATA_DIR, PROBE_NAME + ".csv")


def write_probe(version):
    rng = secrets.SystemRandom()
    start = rng.randrange(10000, 90000)
    baseline = rng.uniform(-20.0, 20.0)
    values = [baseline + rng.uniform(-0.8, 0.8) for _ in range(9)]
    jump = rng.uniform(70.0, 120.0) + version * rng.uniform(5.0, 15.0)
    values.extend([baseline + jump, baseline + jump * 1.04, baseline + jump * 1.09])
    with open(PROBE_PATH, "w") as f:
        f.write("timestamp,drift_score\n")
        for i, value in enumerate(values):
            f.write(f"{start + i},{value:.12f}\n")


def compute_expected_alerts(data_dir):
    expected = {}
    for filename in os.listdir(data_dir):
        if not filename.endswith('.csv'):
            continue
        server_name = filename[:-4]
        filepath = os.path.join(data_dir, filename)

        with open(filepath, 'r') as f:
            lines = f.read().strip().split('\n')

        if len(lines) <= 1:
            expected[server_name] = []
            continue

        data = []
        for line in lines[1:]:
            if not line.strip():
                continue
            parts = line.split(',')
            data.append((int(parts[0]), float(parts[1])))

        if len(data) < 3:
            expected[server_name] = []
            continue

        rolling_avgs = []
        valid_ts = []
        for i in range(2, len(data)):
            avg = (data[i][1] + data[i-1][1] + data[i-2][1]) / 3.0
            rolling_avgs.append(avg)
            valid_ts.append(data[i][0])

        if not rolling_avgs:
            expected[server_name] = []
            continue

        mean = sum(rolling_avgs) / len(rolling_avgs)
        variance = sum((x - mean) ** 2 for x in rolling_avgs) / len(rolling_avgs)
        std = math.sqrt(variance)

        alerts = []
        if std > 0:
            for t, ra in zip(valid_ts, rolling_avgs):
                z = (ra - mean) / std
                if z > 1.5:
                    alerts.append({"timestamp": t, "z_score": round(z, 3)})

        expected[server_name] = alerts

    return expected


def load_and_check_output():
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} was not created."

    with open(JSON_PATH, 'r') as f:
        try:
            actual_alerts = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    expected_alerts = compute_expected_alerts(DATA_DIR)

    # Check that all expected servers are in the output
    for server, alerts in expected_alerts.items():
        assert server in actual_alerts, f"Server '{server}' missing from output JSON."

        # Sort both expected and actual alerts by timestamp for comparison
        expected_sorted = sorted(alerts, key=lambda x: x["timestamp"])
        actual_sorted = sorted(actual_alerts[server], key=lambda x: x["timestamp"])

        assert len(actual_sorted) == len(expected_sorted), f"Alert count mismatch for server '{server}'. Expected {len(expected_sorted)}, got {len(actual_sorted)}."

        for exp, act in zip(expected_sorted, actual_sorted):
            assert exp["timestamp"] == act["timestamp"], f"Timestamp mismatch for server '{server}'. Expected {exp['timestamp']}, got {act['timestamp']}."
            assert math.isclose(exp["z_score"], act["z_score"], abs_tol=0.002), f"Z-score mismatch for server '{server}' at timestamp {exp['timestamp']}. Expected {exp['z_score']}, got {act['z_score']}."

    # Check if there are any extra servers in the output
    for server in actual_alerts:
        assert server in expected_alerts, f"Unexpected server '{server}' found in output JSON."


def cargo_metadata():
    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Invalid Cargo project.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    return json.loads(result.stdout)


def release_binaries(metadata):
    names = set()
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []):
                names.add(target["name"])

    assert names, "Cargo project has no binary target."
    target_dir = metadata["target_directory"]
    found = []
    for name in names:
        patterns = [
            os.path.join(target_dir, "release", name),
            os.path.join(target_dir, "**", "release", name),
        ]
        for pattern in patterns:
            for path in glob.glob(pattern, recursive=True):
                if path not in found and os.path.isfile(path) and os.access(path, os.X_OK):
                    found.append(path)
    return found


def test_pipeline_execution():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    assert os.path.isdir(PROJECT), f"Rust project {PROJECT} does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."

    rust_sources = []
    for root, _, files in os.walk(PROJECT):
        if os.path.basename(root) == "target":
            continue
        rust_sources.extend(os.path.join(root, f) for f in files if f.endswith(".rs"))
    assert rust_sources, "No Rust source files were written in the project."

    metadata = cargo_metadata()
    clean = subprocess.run(["cargo", "clean"], cwd=PROJECT, capture_output=True, text=True, timeout=60)
    assert clean.returncode == 0, f"Could not clean Cargo build artifacts.\n{clean.stderr}"

    write_probe(1)
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    binaries = release_binaries(metadata)
    assert binaries, "The pipeline did not produce an executable release binary."
    for binary in binaries:
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Release artifact {binary} is not a compiled executable."


def test_alerts_json_output():
    # Preserve the original output assertions for the script run.
    load_and_check_output()

    # Change the runtime-only fixture, then execute a compiled Rust release binary
    # directly. This prevents a script that merely emits fixture-specific JSON.
    write_probe(2)
    metadata = cargo_metadata()
    binaries = release_binaries(metadata)
    assert binaries, "No executable Rust release binary is available for testing."

    failures = []
    for binary in binaries:
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        result = subprocess.run([binary], cwd=PROJECT, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            failures.append(f"{binary}: exit {result.returncode}: {result.stderr}")
            continue
        try:
            load_and_check_output()
            return
        except Exception as exc:
            failures.append(f"{binary}: {exc}")

    pytest.fail("No compiled Rust release binary processed the changed input correctly.\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
