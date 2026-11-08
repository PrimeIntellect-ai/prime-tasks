#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import secrets
import struct

import pytest
from scapy.all import rdpcap, UDP

BASE = "/home/user/ticket_4092"
WORKER_PATH = os.path.join(BASE, "worker.py")
SOLUTION_PATH = os.path.join(BASE, "solution.txt")
PCAP_PATH = os.path.join(BASE, "traffic.pcap")


def get_sum_of_proper_divisors(n):
    if n <= 1:
        return 0
    s = 1
    for i in range(2, int(math.isqrt(n)) + 1):
        if n % i == 0:
            s += i
            if i != n // i:
                s += n // i
    return s


def independent_divisor_sum(n):
    if n <= 1:
        return 0
    return sum(d for d in range(1, n) if n % d == 0)


@pytest.fixture(scope="session")
def worker():
    assert os.path.isfile(WORKER_PATH), f"File {WORKER_PATH} is missing."
    spec = importlib.util.spec_from_file_location("submitted_worker", WORKER_PATH)
    assert spec is not None and spec.loader is not None, "worker.py is not importable"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "sum_of_proper_divisors", None))
    assert callable(getattr(module, "process_payload", None))
    return module


def test_solution_file_exists():
    """Test that the solution.txt file exists."""
    file_path = "/home/user/ticket_4092/solution.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. You must create the solution file."


def test_solution_contents():
    """Test that the solution.txt file contains the correct output."""
    file_path = "/home/user/ticket_4092/solution.txt"

    # The numbers encoded in the PCAP file
    expected_numbers = [28, 36, 8128, 100]
    expected_lines = [f"{n}: {get_sum_of_proper_divisors(n)}" for n in expected_numbers]

    with open(file_path, "r") as f:
        content = f.read()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in solution.txt, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} is incorrect.\n"
            f"Expected: '{expected}'\n"
            f"Found: '{actual}'"
        )


def test_divisor_logic_on_derived_inputs(worker):
    values = [0, 1, 2, 3, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121, 169]
    values.extend(2 + secrets.randbelow(20000) for _ in range(20))
    for n in values:
        expected = independent_divisor_sum(n)
        assert worker.sum_of_proper_divisors(n) == expected, (
            f"sum_of_proper_divisors({n}) returned the wrong result"
        )


def test_process_payload_big_endian_and_integration(worker):
    values = [2 + secrets.randbelow(50000) for _ in range(12)]
    for n in values:
        payload = struct.pack(">Q", n)
        assert worker.process_payload(payload) == (n, independent_divisor_sum(n)), (
            "process_payload must decode an 8-byte big-endian payload and calculate its divisor sum"
        )


def test_process_payload_is_unsigned(worker, monkeypatch):
    n = (1 << 63) + secrets.randbelow(1 << 32)
    observed = []

    def fake_sum(value):
        observed.append(value)
        return 7319

    monkeypatch.setattr(worker, "sum_of_proper_divisors", fake_sum)
    assert worker.process_payload(struct.pack(">Q", n)) == (n, 7319)
    assert observed == [n], "The payload must be decoded as an unsigned 64-bit integer"


def test_pcap_payloads_are_processed_by_worker(worker):
    packets = rdpcap(PCAP_PATH)
    payloads = [bytes(packet[UDP].payload) for packet in packets if UDP in packet]
    assert payloads, "No UDP payloads were found in traffic.pcap"

    expected_lines = []
    for payload in payloads:
        assert len(payload) == 8, "Each captured payload must contain one 8-byte integer"
        n = struct.unpack(">Q", payload)[0]
        expected_sum = independent_divisor_sum(n)
        assert worker.process_payload(payload) == (n, expected_sum)
        expected_lines.append(f"{n}: {expected_sum}")

    with open(SOLUTION_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
