#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from decimal import Decimal

from scapy.all import Ether, IP, UDP, Raw, wrpcap

PROJECT = "/home/user/forensics"
EXE = os.path.join(PROJECT, "telemetry_parser")
SOURCE = os.path.join(PROJECT, "telemetry_parser.c")
REPORT = os.path.join(PROJECT, "report.txt")


def run_parser(executable, cwd):
    result = subprocess.run(
        [executable], cwd=cwd, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Parser exited with {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout


def parse_exact_output(output):
    match = re.fullmatch(
        r"Sensor: ([^\n]+)\n"
        r"Count: ([0-9]+)\n"
        r"Mean: (-?[0-9]+\.[0-9]{2})\n"
        r"Variance: ([0-9]+\.[0-9]{4})\n?",
        output,
    )
    assert match is not None, f"Output does not have the required exact format: {output!r}"
    return match.group(1), int(match.group(2)), float(match.group(3)), float(match.group(4))


def make_dynamic_capture(directory):
    rng = secrets.SystemRandom()
    sensor = f"Calibration Array {secrets.token_hex(5)} Unit"
    count = rng.randint(8, 15)
    offsets = [rng.randint(-20, 20) for _ in range(count)]
    while len(set(offsets)) < 4:
        offsets = [rng.randint(-20, 20) for _ in range(count)]

    base = rng.randint(300_000_000, 900_000_000)
    values = [Decimal(base) + Decimal(offset) / Decimal(100) for offset in offsets]
    timestamp = rng.randint(1_700_000_000, 1_900_000_000)

    packets = []
    for index, value in enumerate(values):
        payload = f"[{sensor}] {value:.2f} {timestamp + index}".encode("ascii")
        packets.append(
            Ether()/IP(dst="127.0.0.1")/UDP(sport=12000 + index, dport=9000)/Raw(payload)
        )

    # These records must not be included in the aggregate.
    packets.append(Ether()/IP(dst="127.0.0.1")/UDP(sport=2222, dport=9001)/Raw(b"[Wrong Port Sensor] 1.00 1"))
    packets.append(Ether()/IP(dst="127.0.0.1")/UDP(sport=2223, dport=9000)/Raw(b"malformed telemetry record"))
    wrpcap(os.path.join(directory, "traffic.pcap"), packets)

    mean = sum(values) / Decimal(count)
    variance = sum((value - mean) ** 2 for value in values) / Decimal(count - 1)
    return sensor, count, float(mean), float(variance)


def assert_dynamic_behavior(executable):
    for _ in range(2):
        with tempfile.TemporaryDirectory() as directory:
            expected_sensor, expected_count, expected_mean, expected_variance = make_dynamic_capture(directory)
            output = run_parser(executable, directory)
            sensor, count, mean, variance = parse_exact_output(output)

            assert sensor == expected_sensor, f"Parsed sensor name is wrong: {sensor!r}"
            assert count == expected_count, f"Record count is wrong: {count}"
            assert abs(mean - expected_mean) <= 0.0051, (
                f"Mean is wrong: expected {expected_mean}, got {mean}"
            )
            assert abs(variance - expected_variance) <= 0.000051, (
                f"Sample variance is wrong: expected {expected_variance}, got {variance}"
            )


def test_report_exists():
    assert os.path.isfile(REPORT), "The file /home/user/forensics/report.txt does not exist."


def test_report_content():
    with open(REPORT, "r") as f:
        content = f.read().strip()

    # Preserve the original checks for the supplied capture.
    assert "Sensor: Pressure Sensor A" in content, "The report does not contain the correct Sensor name (expected 'Pressure Sensor A')."
    assert "Count: 10" in content, "The report does not contain the correct Count (expected 10)."
    assert "Mean: 1000000.02" in content, "The report does not contain the correct Mean (expected 1000000.02)."
    variance_match = re.search(r"Variance:\s*([0-9.]+)", content)
    assert variance_match is not None, "The report does not contain a Variance field."
    variance_val = float(variance_match.group(1))
    assert abs(variance_val - 0.0002) < 0.00005, f"The Variance value is incorrect. Expected ~0.0002, got {variance_val}"

    # The report must be the exact output produced by the submitted executable.
    output = run_parser(EXE, PROJECT)
    parse_exact_output(output)
    assert content == output.strip(), "report.txt is not the output of the submitted parser on traffic.pcap."


def test_executable_exists():
    assert os.path.isfile(EXE), f"The executable {EXE} does not exist. Did you run make?"
    assert os.access(EXE, os.X_OK), f"The file {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "telemetry_parser is not a compiled ELF executable."
    assert os.path.getmtime(EXE) >= os.path.getmtime(SOURCE), "The executable is older than telemetry_parser.c; run make after editing."


def test_c_code_modified():
    assert os.path.isfile(SOURCE), f"The file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert content, "telemetry_parser.c is empty."


def test_submitted_executable_on_unseen_captures():
    assert_dynamic_behavior(EXE)


def test_source_builds_and_implements_parser():
    with tempfile.TemporaryDirectory() as build_dir:
        rebuilt = os.path.join(build_dir, "telemetry_parser_rebuilt")
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-o", rebuilt, SOURCE, "-lpcap"],
            text=True, capture_output=True, timeout=20
        )
        assert result.returncode == 0, f"telemetry_parser.c does not compile: {result.stderr}"
        assert_dynamic_behavior(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
