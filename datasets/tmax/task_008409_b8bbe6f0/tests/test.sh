#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import secrets
import subprocess
from datetime import datetime, timedelta, timezone

OUTPUT_FILE = "/home/user/output/final_metrics.csv"
DATA_DIR = "/home/user/data"
EXPECTED_HEADERS = ["timestamp", "ip_address", "datacenter", "cpu_percent", "mem_percent"]


def run_command(command):
    return subprocess.run(command, cwd="/home/user", capture_output=True, text=True)


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    with open(OUTPUT_FILE, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "Output CSV is empty."
    headers = [h.strip() for h in rows[0]]
    assert headers == EXPECTED_HEADERS, f"Headers are incorrect. Expected {EXPECTED_HEADERS}, got {headers}"
    return [[c.strip() for c in row] for row in rows[1:]]


def test_makefile_and_etl_script_exist():
    assert os.path.isfile("/home/user/Makefile"), "Makefile is missing in /home/user/"
    assert os.path.isfile("/home/user/etl.py"), "etl.py is missing in /home/user/"


def test_make_run_and_output():
    # Ensure starting clean if the test is run multiple times
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    # Run make run
    result = run_command(["make", "run"])
    assert result.returncode == 0, f"'make run' failed with error:\n{result.stderr}"

    data_rows = read_output()

    expected_data = [
        ["2023-10-01T10:00:00Z", "10.0.0.1", "us-east-1", "50.0", "50.0"],
        ["2023-10-01T10:00:00Z", "10.0.0.2", "eu-west-1", "10.0", "12.5"],
        ["2023-10-01T10:05:00Z", "10.0.0.1", "us-east-1", "60.0", "53.1"],
        ["2023-10-01T10:05:00Z", "10.0.0.3", "ap-south-1", "90.0", "100.0"]
    ]

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(data_rows)}."
    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"

    # Test idempotency
    with open(OUTPUT_FILE, "r") as f:
        content_before = f.read()

    result_again = run_command(["make", "run"])
    assert result_again.returncode == 0, f"Second 'make run' failed with error:\n{result_again.stderr}"

    with open(OUTPUT_FILE, "r") as f:
        content_after = f.read()

    assert content_before == content_after, "Pipeline is not idempotent. Output changed or duplicated after second run."


def test_pipeline_with_runtime_generated_inputs():
    paths = [
        os.path.join(DATA_DIR, "raw_logs.txt"),
        os.path.join(DATA_DIR, "capacities.csv"),
        os.path.join(DATA_DIR, "locations.csv"),
    ]
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    rng = random.SystemRandom()
    token = secrets.token_hex(4)

    ips = set()
    while len(ips) < 4:
        ips.add(f"172.{rng.randrange(16, 30)}.{rng.randrange(1, 255)}.{rng.randrange(1, 255)}")
    ips = sorted(ips)

    start = datetime(2025, rng.randrange(1, 10), rng.randrange(1, 20), rng.randrange(0, 18), 3, tzinfo=timezone.utc)
    timestamps = [
        (start + timedelta(minutes=offset)).strftime("%Y-%m-%dT%H:%M:%SZ")
        for offset in (0, 11, 29)
    ]

    nodes = {}
    for index, ip in enumerate(ips):
        nodes[ip] = {
            "max_cpu": rng.randrange(1, 8) * 1000,
            "max_mem": rng.randrange(8, 33) * 1000,
            "datacenter": f"runtime-{token}-{index}",
        }

    combinations = [
        (timestamps[0], ips[2]),
        (timestamps[0], ips[0]),
        (timestamps[1], ips[3]),
        (timestamps[1], ips[1]),
        (timestamps[2], ips[0]),
        (timestamps[2], ips[2]),
    ]

    metrics = []
    expected = []
    for timestamp, ip in combinations:
        cpu_tenths_percent = rng.randrange(37, 951)
        mem_tenths_percent = rng.randrange(41, 951)
        cpu = nodes[ip]["max_cpu"] * cpu_tenths_percent // 1000
        mem = nodes[ip]["max_mem"] * mem_tenths_percent // 1000
        metrics.append((timestamp, ip, "cpu", cpu))
        metrics.append((timestamp, ip, "mem", mem))
        expected.append([
            timestamp,
            ip,
            nodes[ip]["datacenter"],
            f"{cpu / nodes[ip]['max_cpu'] * 100:.1f}",
            f"{mem / nodes[ip]['max_mem'] * 100:.1f}",
        ])

    # Add exact duplicate log lines and disorder the long-form input.
    metrics.extend([metrics[1], metrics[4], metrics[4], metrics[-1]])
    rng.shuffle(metrics)
    expected.sort(key=lambda row: (row[0], row[1]))

    try:
        with open(paths[0], "w", newline="") as f:
            for timestamp, ip, key, value in metrics:
                f.write(f"[{timestamp}] node_ip={ip} type=metric key={key} val={value}\n")

        with open(paths[1], "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["ip_address", "max_cpu", "max_mem"])
            capacity_rows = [[ip, nodes[ip]["max_cpu"], nodes[ip]["max_mem"]] for ip in ips]
            rng.shuffle(capacity_rows)
            writer.writerows(capacity_rows)

        with open(paths[2], "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["ip_address", "datacenter"])
            location_rows = [[ip, nodes[ip]["datacenter"]] for ip in ips]
            rng.shuffle(location_rows)
            writer.writerows(location_rows)

        # Execute the requested Python artifact directly on the generated inputs.
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        direct = run_command(["python3", "/home/user/etl.py"])
        assert direct.returncode == 0, f"Direct execution of etl.py failed:\n{direct.stderr}"
        direct_rows = read_output()
        assert direct_rows == expected, f"etl.py produced incorrect data for generated inputs. Expected {expected}, got {direct_rows}"

        # The Make target must produce the same result and remain idempotent.
        os.remove(OUTPUT_FILE)
        first = run_command(["make", "run"])
        assert first.returncode == 0, f"'make run' failed on generated inputs:\n{first.stderr}"
        make_rows = read_output()
        assert make_rows == expected, f"make run produced incorrect data for generated inputs. Expected {expected}, got {make_rows}"

        with open(OUTPUT_FILE, "rb") as f:
            content_before = f.read()
        second = run_command(["make", "run"])
        assert second.returncode == 0, f"Second 'make run' failed on generated inputs:\n{second.stderr}"
        with open(OUTPUT_FILE, "rb") as f:
            content_after = f.read()
        assert content_before == content_after, "Pipeline is not idempotent on generated inputs."
    finally:
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
