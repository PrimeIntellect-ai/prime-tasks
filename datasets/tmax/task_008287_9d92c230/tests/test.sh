#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import csv
import re
import signal
import subprocess
import pytest

REPORT_PATH = "/home/user/debug_report.json"
STATS_PATH = "/home/user/build_stats.csv"
DUMP_PATH = "/home/user/goroutine_dump.txt"
PCAP_PATH = "/home/user/app/traffic.pcap"
MAIN_PATH = "/home/user/app/main.go"
APP_DIR = "/home/user/app"


def derive_anomalous_size():
    with open(STATS_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["status"] == "timeout":
                return int(row["max_packet_size"])
    pytest.fail("Could not derive anomalous packet size from stats.")


def run_main(timeout=30):
    process = subprocess.Popen(
        ["go", "run", "main.go"],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        pytest.fail("go run main.go timed out; the synchronization deadlock remains.")

    assert process.returncode == 0, (
        f"go run main.go failed with exit code {process.returncode}. stderr: {stderr}"
    )
    return stdout.strip()


def test_debug_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected {REPORT_PATH} to exist."


def test_debug_report_content():
    # Derive anomalous packet size from the build stats
    anomalous_size = None
    with open(STATS_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["status"] == "timeout":
                anomalous_size = int(row["max_packet_size"])
                break
    assert anomalous_size is not None, "Could not derive anomalous packet size from stats."

    # Derive extracted payload from the goroutine dump
    extracted_payload = None
    with open(DUMP_PATH, "r") as f:
        content = f.read()
        match = re.search(r'last_payload\s*=\s*"([^"]+)"', content)
        if match:
            extracted_payload = match.group(1)
    assert extracted_payload is not None, "Could not derive payload from dump."

    # Derive the expected final output based on the pcap file and anomalous size
    normal_packets = 0
    with open(PCAP_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 2:
                size = int(parts[0])
                if size != anomalous_size:
                    normal_packets += 1

    expected_output = f"Success! Processed {normal_packets} normal packets."

    # Load and verify the JSON report
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON.")

    assert "anomalous_packet_size" in report, "Missing 'anomalous_packet_size' in JSON."
    assert report["anomalous_packet_size"] == anomalous_size, f"Incorrect anomalous_packet_size. Expected {anomalous_size}."

    assert "extracted_payload" in report, "Missing 'extracted_payload' in JSON."
    assert report["extracted_payload"] == extracted_payload, f"Incorrect extracted_payload. Expected '{extracted_payload}'."

    assert "fixed_output" in report, "Missing 'fixed_output' in JSON."
    assert report["fixed_output"].strip() == expected_output, f"Incorrect fixed_output. Expected '{expected_output}'."


def test_main_go_runs_and_matches_report():
    assert os.path.isfile(MAIN_PATH), f"Expected {MAIN_PATH} to be a Go source file."

    anomalous_size = derive_anomalous_size()
    normal_packets = 0
    with open(PCAP_PATH, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 2 and int(parts[0]) != anomalous_size:
                normal_packets += 1
    expected_output = f"Success! Processed {normal_packets} normal packets."

    actual_output = run_main()
    assert actual_output == expected_output, (
        f"Unexpected output from go run main.go. Expected '{expected_output}', got '{actual_output}'."
    )

    with open(REPORT_PATH, "r") as f:
        report = json.load(f)
    assert report["fixed_output"].strip() == actual_output, (
        "fixed_output does not match the actual output from go run main.go."
    )


def test_main_go_handles_repeated_anomalous_packets_without_deadlock():
    anomalous_size = derive_anomalous_size()
    regular_sizes = [anomalous_size + 1, anomalous_size + 2, anomalous_size + 3]
    original_pcap = open(PCAP_PATH, "rb").read()

    cases = [
        [
            (anomalous_size, "TRIGGER_ONE"),
            (regular_sizes[0], "NORMAL_ONE"),
            (anomalous_size, "TRIGGER_TWO"),
            (regular_sizes[1], "NORMAL_TWO"),
        ],
        [
            (regular_sizes[0], "NORMAL_ONE"),
            (regular_sizes[1], "NORMAL_TWO"),
            (regular_sizes[2], "NORMAL_THREE"),
        ],
    ]

    try:
        for packets in cases:
            with open(PCAP_PATH, "w") as f:
                for size, payload in packets:
                    f.write(f"{size},{payload}\n")

            expected_count = sum(1 for size, _ in packets if size != anomalous_size)
            expected_output = f"Success! Processed {expected_count} normal packets."
            actual_output = run_main()
            assert actual_output == expected_output, (
                f"Unexpected output for verifier-generated traffic. Expected "
                f"'{expected_output}', got '{actual_output}'."
            )
    finally:
        with open(PCAP_PATH, "wb") as f:
            f.write(original_pcap)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
