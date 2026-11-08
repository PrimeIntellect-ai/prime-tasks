#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import string
import subprocess

import pytest

INPUT_PATH = "/home/user/raw_configs.txt"
OUTPUT_PATH = "/home/user/changepoints.csv"


def compute_expected_changepoints(input_path):
    if not os.path.isfile(input_path):
        pytest.fail(f"Input file {input_path} is missing, cannot compute expected state.")

    data = []
    with open(input_path, "r") as f:
        for line in f:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 4:
                continue
            timestamp = int(parts[0])
            server_id = parts[1]
            raw_log = parts[2]
            cpu_limit_str = parts[3]

            match = re.search(r"hash=\[([a-zA-Z0-9]{6})\]", raw_log)
            config_hash = match.group(1) if match else ""
            cpu_limit = float(cpu_limit_str) if cpu_limit_str else None

            data.append({
                "timestamp": timestamp,
                "server_id": server_id,
                "config_hash": config_hash,
                "cpu_limit": cpu_limit,
            })

    servers = {}
    for row in data:
        servers.setdefault(row["server_id"], []).append(row)

    expected_rows = []
    for server_id in sorted(servers.keys()):
        server_data = sorted(servers[server_id], key=lambda x: x["timestamp"])

        for i, row in enumerate(server_data):
            if row["cpu_limit"] is None:
                t0, v0 = None, None
                for prev_row in reversed(server_data[:i]):
                    if prev_row["cpu_limit"] is not None:
                        t0, v0 = prev_row["timestamp"], prev_row["cpu_limit"]
                        break

                t1, v1 = None, None
                for next_row in server_data[i + 1:]:
                    if next_row["cpu_limit"] is not None:
                        t1, v1 = next_row["timestamp"], next_row["cpu_limit"]
                        break

                if t0 is not None and t1 is not None and t1 != t0:
                    row["cpu_limit"] = v0 + (v1 - v0) * (row["timestamp"] - t0) / (t1 - t0)

        prev_hash = None
        prev_cpu = None
        for row in server_data:
            curr_hash = row["config_hash"]
            curr_cpu = round(row["cpu_limit"], 2) if row["cpu_limit"] is not None else None

            if prev_hash is None:
                expected_rows.append(row)
                prev_hash = curr_hash
                prev_cpu = curr_cpu
            elif curr_hash != prev_hash or curr_cpu != prev_cpu:
                expected_rows.append(row)
                prev_hash = curr_hash
                prev_cpu = curr_cpu

    expected_output = [["timestamp", "server_id", "config_hash", "cpu_limit"]]
    for row in expected_rows:
        cpu_formatted = f"{row['cpu_limit']:.2f}" if row["cpu_limit"] is not None else ""
        expected_output.append([
            str(row["timestamp"]),
            row["server_id"],
            row["config_hash"],
            cpu_formatted,
        ])
    return expected_output


def read_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, "r", newline="") as f:
        return list(csv.reader(f))


def assert_output_matches_expected():
    expected_data = compute_expected_changepoints(INPUT_PATH)
    actual_data = read_output()

    assert len(actual_data) > 0, f"The file {OUTPUT_PATH} is empty."
    assert actual_data[0] == ["timestamp", "server_id", "config_hash", "cpu_limit"], \
        f"CSV header in {OUTPUT_PATH} is incorrect. Expected {expected_data[0]}, got {actual_data[0]}."
    assert len(actual_data) == len(expected_data), \
        f"Row count mismatch. Expected {len(expected_data)} rows (including header), got {len(actual_data)}."

    for i in range(1, len(expected_data)):
        assert actual_data[i] == expected_data[i], \
            f"Mismatch at row {i + 1}. Expected {expected_data[i]}, got {actual_data[i]}."


def test_changepoints_csv_exists():
    assert os.path.isfile(OUTPUT_PATH), \
        f"Output file {OUTPUT_PATH} is missing. Did your Rust program run successfully?"


def test_changepoints_csv_content():
    assert_output_matches_expected()


def find_cargo_projects():
    roots = [
        "/home", "/root", "/tmp", "/workspace", "/workspaces",
        "/app", "/opt", "/project", "/projects", "/mnt", "/usr/local",
    ]
    pruned = {"target", ".cargo", ".rustup", ".git", "node_modules", "__pycache__"}
    manifests = []

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in pruned]
            if "Cargo.toml" not in files:
                continue

            manifest = os.path.join(current, "Cargo.toml")
            has_rust_source = False
            for source_root, source_dirs, source_files in os.walk(current):
                source_dirs[:] = [d for d in source_dirs if d not in pruned]
                if any(name.endswith(".rs") for name in source_files):
                    has_rust_source = True
                    break
            if has_rust_source:
                manifests.append(manifest)

    return sorted(set(manifests), key=lambda p: (not p.startswith("/home/user/"), len(p), p))


def write_fixture(rows):
    with open(INPUT_PATH, "w") as f:
        for timestamp, server_id, raw_log, cpu_limit in rows:
            f.write(f"{timestamp} | {server_id} | {raw_log} | {cpu_limit}\n")


def run_cargo_project(manifest):
    common = {
        "cwd": os.path.dirname(manifest),
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "timeout": 120,
    }
    try:
        built = subprocess.run(
            ["cargo", "build", "--quiet", "--manifest-path", manifest],
            **common,
        )
        if built.returncode != 0:
            return False
        ran = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", manifest],
            **common,
        )
        return ran.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def random_hash(rng):
    alphabet = string.ascii_letters + string.digits
    return "".join(rng.choice(alphabet) for _ in range(6))


def test_rust_cargo_program_builds_runs_and_handles_fresh_inputs():
    manifests = find_cargo_projects()
    assert manifests, "No Rust Cargo project containing Rust source files was found."

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    rng = random.SystemRandom()
    base = rng.randrange(20000, 90000)
    suffix = "".join(rng.choice(string.ascii_lowercase) for _ in range(7))
    server_a = f"alpha-{suffix}"
    server_b = f"zeta-{suffix}"
    h1, h2, h3 = random_hash(rng), random_hash(rng), random_hash(rng)

    fixture_one = [
        (base + 30, server_b, f"notice applied hash=[{h1}] ok", "8.0"),
        (base + 15, server_a, f"boot hash=[{h3}] ready", "1.25"),
        (base + 10, server_b, f"start hash=[{h1}] ready", "4.0"),
        (base + 25, server_a, f"retry hash=[{h3}] duplicate", "1.25"),
        (base + 20, server_b, f"retry hash=[{h1}] pending", ""),
        (base + 35, server_a, f"metric hash=[{h3}] changed", "2.25"),
        (base + 50, server_b, f"switch hash=[{h2}] complete", "8.0"),
        (base + 40, server_b, f"retry hash=[{h1}] duplicate", "8.0"),
    ]

    chosen_manifest = None
    try:
        for manifest in manifests:
            write_fixture(fixture_one)
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            if not run_cargo_project(manifest):
                continue
            try:
                assert_output_matches_expected()
                chosen_manifest = manifest
                break
            except AssertionError:
                continue

        assert chosen_manifest is not None, \
            "No discovered Cargo program generated the correct CSV for a fresh input fixture."

        base2 = rng.randrange(100000, 190000)
        h4, h5, h6 = random_hash(rng), random_hash(rng), random_hash(rng)
        fixture_two = [
            (base2 + 40, server_a, f"tail hash=[{h5}] duplicate", "12.0"),
            (base2 + 20, server_a, f"middle hash=[{h4}] observed", "12.0"),
            (base2 + 5, server_b, f"first hash=[{h6}] seen", "3.5"),
            (base2 + 10, server_a, f"missing hash=[{h4}] sample", ""),
            (base2 + 30, server_a, f"change hash=[{h5}] applied", "12.0"),
            (base2, server_a, f"initial hash=[{h4}] applied", "10.0"),
            (base2 + 25, server_b, f"again hash=[{h6}] seen", "3.5"),
        ]
        write_fixture(fixture_two)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        assert run_cargo_project(chosen_manifest), \
            f"Cargo project {chosen_manifest} failed when run on a second fresh fixture."
        assert_output_matches_expected()
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
