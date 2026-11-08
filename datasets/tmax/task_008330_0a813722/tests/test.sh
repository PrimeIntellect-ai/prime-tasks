#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile
from collections import defaultdict


def test_alerts_tsv_exists_and_content():
    alerts_path = "/home/user/alerts.tsv"
    assert os.path.exists(alerts_path), f"Output file {alerts_path} does not exist. Did you run your C++ program to generate it?"

    with open(alerts_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Subnet\tHour\tPreviousCount\tCurrentCount",
        "172.16.20\t2023-10-01T15\t60\t10",
        "192.168.1\t2023-10-01T11\t100\t15"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {alerts_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {alerts_path} mismatch.\nExpected: '{expected}'\nGot:      '{actual}'"


def test_cpp_file_exists():
    cpp_path = "/home/user/process_logs.cpp"
    assert os.path.exists(cpp_path), f"C++ source file {cpp_path} does not exist."
    assert os.path.isfile(cpp_path), f"{cpp_path} is not a regular source file."


def reference_output(raw_lines):
    counts = defaultdict(int)
    for raw in raw_lines:
        fields = raw.split()
        if len(fields) != 4:
            continue
        timestamp, ip, event_name, status = fields
        if len(timestamp) != 19:
            continue
        if ip.count('.') != 3:
            continue
        if len(status) != 3 or not status.isdigit():
            continue
        hour = timestamp[:13]
        subnet = '.'.join(ip.split('.')[:3])
        counts[(subnet, hour)] += 1

    anomalies = []
    for (subnet, hour), current in counts.items():
        date = hour[:10]
        try:
            hour_number = int(hour[11:13])
        except ValueError:
            continue
        if hour_number == 0:
            continue
        previous_hour = f"{date}T{hour_number - 1:02d}"
        previous = counts.get((subnet, previous_hour))
        if previous is not None and previous >= 50 and current < 0.20 * previous:
            anomalies.append((subnet, hour, previous, current))

    anomalies.sort(key=lambda row: (row[0], row[1]))
    return ["Subnet\tHour\tPreviousCount\tCurrentCount"] + [
        f"{subnet}\t{hour}\t{previous}\t{current}"
        for subnet, hour, previous, current in anomalies
    ]


def make_dynamic_input():
    token = secrets.randbelow(180) + 20
    subnets = [
        f"10.{token}.7",
        f"172.{(token + 31) % 200 + 20}.9",
        f"192.168.{(token + 67) % 200 + 20}",
        f"100.{(token + 91) % 200 + 20}.4",
    ]
    lines = []

    def add(subnet, hour, count, status="200"):
        for i in range(count):
            minute = (i * 7 + token) % 60
            second = (i * 11 + 3) % 60
            host = i % 250 + 1
            lines.append(f"2025-02-03T{hour:02d}:{minute:02d}:{second:02d} {subnet}.{host} EVENT_{i % 5} {status}")

    # Two genuine drops for one subnet, including a non-round threshold.
    first_previous = 61 + secrets.randbelow(35)
    first_current = max(1, (first_previous - 1) // 5)
    add(subnets[0], 8, first_previous)
    add(subnets[0], 9, first_current)
    add(subnets[0], 14, 55)
    add(subnets[0], 15, 10)

    # Exactly 20 percent is not a strict drop.
    add(subnets[1], 10, 75)
    add(subnets[1], 11, 15)

    # A gap between hours is not consecutive.
    add(subnets[2], 18, 90)
    add(subnets[2], 20, 1)

    # A previous count below 50 cannot trigger an anomaly.
    add(subnets[3], 6, 49)
    add(subnets[3], 7, 1)

    # If accepted, each invalid group would inflate a genuine drop enough to hide it.
    for i in range(80):
        host = i % 250 + 1
        lines.append(f"2025-02-03T09:{i % 60:02d} {subnets[0]}.{host} BAD 200")  # short timestamp
        lines.append(f"2025-02-03T09:{i % 60:02d}:00 {subnets[0]}.{host}.8 BAD 200")  # four periods
        lines.append(f"2025-02-03T09:{i % 60:02d}:00 {subnets[0]}.{host} BAD 20")  # short status
        lines.append(f"2025-02-03T09:{i % 60:02d}:00 {subnets[0]}.{host} BAD 2O0")  # non-digit status
        lines.append(f"2025-02-03T09:{i % 60:02d}:00 {subnets[0]}.{host} BAD 200 EXTRA")

    random.SystemRandom().shuffle(lines)
    return lines


def run_and_check(binary, input_path, output_path, expected):
    result = subprocess.run(
        [binary, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(output_path), f"{binary} did not create its requested output file."
    with open(output_path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Dynamic output mismatch.\nExpected: {expected!r}\nGot: {actual!r}"


def test_source_compiles_and_program_processes_unseen_input():
    source = "/home/user/process_logs.cpp"
    installed_binary = "/home/user/process_logs"

    assert os.path.isfile(installed_binary), f"Compiled program {installed_binary} does not exist."
    assert os.access(installed_binary, os.X_OK), f"Compiled program {installed_binary} is not executable."
    with open(installed_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{installed_binary} is not a compiled ELF executable."

    raw_lines = make_dynamic_input()
    expected = reference_output(raw_lines)

    with tempfile.TemporaryDirectory(prefix="verify_logs_") as tmp:
        input_path = os.path.join(tmp, "unseen_events.txt")
        fresh_binary = os.path.join(tmp, "process_logs_fresh")
        fresh_output = os.path.join(tmp, "fresh_alerts.tsv")
        installed_output = os.path.join(tmp, "installed_alerts.tsv")
        with open(input_path, "w") as f:
            f.write("\n".join(raw_lines) + "\n")

        compile_result = subprocess.run(
            ["/usr/bin/g++", "-O3", "-std=c++17", source, "-o", fresh_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"The submitted C++ source did not compile.\nstdout:\n{compile_result.stdout}\n"
            f"stderr:\n{compile_result.stderr}"
        )

        run_and_check(fresh_binary, input_path, fresh_output, expected)
        run_and_check(installed_binary, input_path, installed_output, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
