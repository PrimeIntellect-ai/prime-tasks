#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess

import pytest

INPUT_FILE = "/home/user/raw_logs.json"
OUTPUT_FILE = "/home/user/processed_logs.csv"
PROJECT_DIR = "/home/user/log_processor"
EXPECTED_HEADERS = [
    "timestamp",
    "event_type",
    "method",
    "normalized_path",
    "masked_ip",
    "anonymized_user_id",
]


def get_expected_data(input_file=INPUT_FILE):
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    with open(input_file, "r") as f:
        data = json.load(f)

    expected_rows = []
    for session in data:
        client_ip = session.get("client_ip", "")
        user_id = session.get("user_id", "")

        # Mask IP
        if "." in client_ip:
            ip_parts = client_ip.split(".")
            ip_parts[-1] = "0"
            masked_ip = ".".join(ip_parts)
        else:
            masked_ip = client_ip

        # Anonymize user_id
        anonymized_user_id = hashlib.sha256(user_id.encode("utf-8")).hexdigest()

        for event in session.get("events", []):
            timestamp = event.get("timestamp", "")
            event_type = event.get("event_type", "")
            request = event.get("request", "")

            # Parse request
            parts = request.split()
            if len(parts) >= 2:
                method = parts[0]
                raw_path = parts[1]

                # Normalize path
                path_segments = raw_path.split("/")
                norm_segments = ["{id}" if seg.isdigit() else seg for seg in path_segments]
                normalized_path = "/".join(norm_segments)
            else:
                method = "UNKNOWN"
                normalized_path = "UNKNOWN"

            expected_rows.append([
                timestamp,
                event_type,
                method,
                normalized_path,
                masked_ip,
                anonymized_user_id,
            ])

    # Sort by timestamp ascending
    expected_rows.sort(key=lambda x: x[0])
    return expected_rows


def assert_csv_matches(input_file=INPUT_FILE):
    expected_rows = get_expected_data(input_file)

    with open(OUTPUT_FILE, "r", newline="") as f:
        actual_data = list(csv.reader(f))

    assert len(actual_data) > 0, "The CSV file is empty."
    actual_headers = actual_data[0]
    assert actual_headers == EXPECTED_HEADERS, (
        f"CSV headers are incorrect. Expected {EXPECTED_HEADERS}, got {actual_headers}"
    )

    actual_rows = actual_data[1:]
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows, but found {len(actual_rows)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nGot: {actual}"


def test_processed_logs_csv_exists():
    """Test that the processed_logs.csv file was created."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."


def test_processed_logs_content():
    """Test that the CSV content matches the expected ETL output."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert_csv_matches()


def test_rust_project_builds_and_processes_fresh_input():
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} is missing."
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} is missing."

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT_DIR):
        dirs[:] = [d for d in dirs if d != "target"]
        rust_sources.extend(
            os.path.join(root, name) for name in files if name.endswith(".rs")
        )
    assert rust_sources, "The project contains no Rust source files."

    cargo_env = os.environ.copy()
    cargo_env["HOME"] = "/home/user"
    cargo_env["CARGO_HOME"] = "/home/user/.cargo"

    clean = subprocess.run(
        ["cargo", "clean", "--manifest-path", manifest],
        cwd=PROJECT_DIR,
        env=cargo_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}"

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", manifest],
        cwd=PROJECT_DIR,
        env=cargo_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust project failed to compile:\n{build.stdout}"

    fresh_input = [
        {
            "session_id": "fresh_1",
            "client_ip": "172.20.14.231",
            "user_id": "verification-user-A",
            "events": [
                {
                    "timestamp": "2024-07-02T12:30:00Z",
                    "event_type": "purchase,confirmed",
                    "request": "PATCH /shops/41/orders/9007/status HTTP/2",
                },
                {
                    "timestamp": "2024-01-01T00:00:01Z",
                    "event_type": "bad_request",
                    "request": "INVALID",
                },
            ],
        },
        {
            "session_id": "fresh_2",
            "client_ip": "203.0.113.87",
            "user_id": "verification-user-B",
            "events": [
                {
                    "timestamp": "2024-03-05T08:09:10Z",
                    "event_type": "view",
                    "request": "GET /v2/reports/123/sections/alpha HTTP/1.1",
                },
                {
                    "timestamp": "2024-03-05T08:09:11Z",
                    "event_type": "empty",
                    "request": "",
                },
            ],
        },
    ]

    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()
    with open(OUTPUT_FILE, "rb") as f:
        original_output = f.read()

    try:
        with open(INPUT_FILE, "w") as f:
            json.dump(fresh_input, f)
        os.remove(OUTPUT_FILE)

        run = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", manifest],
            cwd=PROJECT_DIR,
            env=cargo_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert run.returncode == 0, f"Compiled Rust program failed to run:\n{run.stdout}"
        assert os.path.isfile(OUTPUT_FILE), "Running the Rust program did not create processed_logs.csv."
        assert_csv_matches()
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        with open(OUTPUT_FILE, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
