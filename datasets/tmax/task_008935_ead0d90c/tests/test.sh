#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import random
import select
import subprocess
from collections import defaultdict

import pytest

PROJECT = "/home/user/aggregator"
BINARY = None


def run_as_user(command, **kwargs):
    return subprocess.run(["runuser", "-u", "user", "--"] + command, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def build_rust_program():
    global BINARY

    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    main_rs = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.exists(cargo_toml), "Rust project Cargo.toml is missing."
    assert os.path.exists(main_rs), "Rust project src/main.rs is missing."

    metadata_result = run_as_user(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", cargo_toml],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"cargo metadata failed:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)

    manifest_real = os.path.realpath(cargo_toml)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert len(packages) == 1, "Could not identify the submitted Cargo package."
    package = packages[0]
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Cargo project does not define a binary target."

    default_run = package.get("default_run")
    if default_run:
        selected = [t for t in bins if t["name"] == default_run]
    else:
        selected = [t for t in bins if t["name"] == package["name"]]
        if not selected and len(bins) == 1:
            selected = bins
    assert len(selected) == 1, "The Cargo project has no unambiguous default binary."

    build_result = run_as_user(
        ["cargo", "build", "--release", "--manifest-path", cargo_toml, "--bin", selected[0]["name"]],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert build_result.returncode == 0, f"Rust release build failed:\n{build_result.stderr}"

    BINARY = os.path.join(metadata["target_directory"], "release", selected[0]["name"])
    assert os.path.isfile(BINARY), f"Built executable is missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Built artifact is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cargo did not produce a native executable."


def test_rust_project_exists():
    assert os.path.exists("/home/user/aggregator/Cargo.toml"), "Rust project Cargo.toml is missing."
    assert os.path.exists("/home/user/aggregator/src/main.rs"), "Rust project src/main.rs is missing."


def test_pipeline_log():
    log_file = "/home/user/pipeline.log"
    assert os.path.exists(log_file), f"Log file {log_file} is missing."

    with open(log_file, "r") as f:
        logs = f.read()

    expected_logs = [
        "Processed 50000 records",
        "Processed 100000 records",
        "Processed 150000 records"
    ]

    for expected in expected_logs:
        assert expected in logs, f"Expected log statement '{expected}' not found in {log_file}."


def test_aggregated_jsonl():
    csv_file = "/home/user/sensor_data.csv"
    jsonl_file = "/home/user/aggregated.jsonl"

    assert os.path.exists(jsonl_file), f"Output file {jsonl_file} is missing."

    data = defaultdict(list)
    with open(csv_file, "r") as f:
        for line in f:
            if not line.strip():
                continue
            ts_str, val_str = line.strip().split(",")
            ts = int(ts_str)
            val = float(val_str)
            bucket = ts - (ts % 3600)
            data[bucket].append(val)

    expected = []
    for bucket in sorted(data.keys()):
        vals = data[bucket]
        count = len(vals)
        mean = sum(vals) / count
        variance = sum((x - mean) ** 2 for x in vals) / count
        expected.append({
            "hour_start": bucket,
            "count": count,
            "mean": mean,
            "variance": variance
        })

    agent_output = []
    with open(jsonl_file, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                agent_output.append(json.loads(line.strip()))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line in {jsonl_file}: {line.strip()}")

    assert len(expected) == len(agent_output), f"Length mismatch: expected {len(expected)} records, got {len(agent_output)}."

    for exp, agt in zip(expected, agent_output):
        assert "hour_start" in agt, "Missing 'hour_start' key in JSON output."
        assert "count" in agt, "Missing 'count' key in JSON output."
        assert "mean" in agt, "Missing 'mean' key in JSON output."
        assert "variance" in agt, "Missing 'variance' key in JSON output."

        assert exp["hour_start"] == agt["hour_start"], f"Mismatch in hour_start: expected {exp['hour_start']}, got {agt['hour_start']}."
        assert exp["count"] == agt["count"], f"Mismatch in count for bucket {exp['hour_start']}: expected {exp['count']}, got {agt['count']}."
        assert abs(exp["mean"] - agt["mean"]) <= 1e-4, f"Mean mismatch for bucket {exp['hour_start']}: expected {exp['mean']}, got {agt['mean']}."
        assert abs(exp["variance"] - agt["variance"]) <= 1e-4, f"Variance mismatch for bucket {exp['hour_start']}: expected {exp['variance']}, got {agt['variance']}."


def test_built_program_on_unseen_stream():
    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    expected_values = defaultdict(list)
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env["HOME"] = user.pw_dir
    proc = subprocess.Popen(
        [BINARY],
        cwd=PROJECT,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=demote,
    )

    def make_line(i):
        # Deliberately unsorted timestamps, including exact hour boundaries.
        bucket_index = rng.randrange(0, 41)
        offset = 0 if i % 997 == 0 else rng.randrange(0, 3600)
        ts = 1800000000 + bucket_index * 3600 + offset
        value = rng.randrange(-1000000, 1000001) / 1000.0
        bucket = ts - (ts % 3600)
        expected_values[bucket].append(value)
        return f"{ts},{value:.6f}\n".encode()

    first_log = None
    try:
        for start in range(0, 50000, 1000):
            proc.stdin.write(b"".join(make_line(i) for i in range(start, start + 1000)))
        proc.stdin.flush()

        ready, _, _ = select.select([proc.stderr], [], [], 20)
        assert ready, "The program did not report 50000 records while stdin was still open; input is not being processed as a stream."
        first_log = proc.stderr.readline().decode("utf-8", errors="replace").rstrip("\r\n")
        assert first_log == "Processed 50000 records", f"Unexpected progress output: {first_log!r}"

        for start in range(50000, 100003, 1000):
            end = min(start + 1000, 100003)
            proc.stdin.write(b"".join(make_line(i) for i in range(start, end)))
        proc.stdin.close()
        proc.stdin = None
        stdout, remaining_stderr = proc.communicate(timeout=45)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()

    assert proc.returncode == 0, f"Built program exited with status {proc.returncode}."
    remaining_logs = remaining_stderr.decode("utf-8", errors="replace").splitlines()
    assert remaining_logs == ["Processed 100000 records"], f"Unexpected progress log lines: {[first_log] + remaining_logs}"

    actual = []
    for raw_line in stdout.decode("utf-8", errors="strict").splitlines():
        if raw_line.strip():
            try:
                actual.append(json.loads(raw_line))
            except json.JSONDecodeError:
                pytest.fail(f"Built program emitted invalid JSON: {raw_line}")

    expected_buckets = sorted(expected_values)
    assert len(actual) == len(expected_buckets), f"Expected {len(expected_buckets)} output buckets, got {len(actual)}."

    for bucket, record in zip(expected_buckets, actual):
        assert all(k in record for k in ("hour_start", "count", "mean", "variance")), f"Missing required key in {record!r}."
        values = expected_values[bucket]
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / len(values)
        assert record["hour_start"] == bucket
        assert record["count"] == len(values)
        assert abs(record["mean"] - mean) <= 1e-4
        assert abs(record["variance"] - variance) <= 1e-4
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
