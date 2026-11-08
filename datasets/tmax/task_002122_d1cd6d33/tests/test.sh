#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys

import pytest
from scapy.all import IP, UDP, Raw, rdpcap


def poison_pill_from_capture():
    capture_path = "/home/user/traffic.pcap"
    assert os.path.isfile(capture_path), f"Packet capture is missing at {capture_path}"

    values = []
    for packet in rdpcap(capture_path):
        if packet.haslayer(IP) and packet.haslayer(UDP) and packet[UDP].dport == 8888 and packet.haslayer(Raw):
            try:
                payload = json.loads(bytes(packet[Raw].load).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            value = payload.get("value")
            if isinstance(value, int) and not isinstance(value, bool):
                values.append(value)

    assert values, "No integer JSON values destined for UDP port 8888 were found in the capture."
    return values[-1]


def test_incident_report_contents():
    """Verify the report has exactly the captured poison pill and SUCCESS."""
    report_path = "/home/user/incident_report.txt"
    assert os.path.exists(report_path), f"Incident report is missing at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() != ""]
    assert len(lines) == 2, f"Expected exactly 2 lines in incident report, found {len(lines)}."
    assert lines[0] == "0", f"Expected the first line to be the poison pill value '0', but got '{lines[0]}'."
    assert lines[1] == "SUCCESS", f"Expected the second line to be 'SUCCESS', but got '{lines[1]}'."

    expected = poison_pill_from_capture()
    assert expected == 0, f"Unexpected final captured integer: {expected}"
    assert content.splitlines() == [str(expected), "SUCCESS"], "Report does not strictly match the requested two-line format."


def test_validate_script_passes():
    """Run the requested validation script and ensure it exits successfully."""
    validate_path = "/home/user/validate.py"
    assert os.path.exists(validate_path), f"Validation script missing at {validate_path}"

    try:
        result = subprocess.run(
            [sys.executable, validate_path],
            capture_output=True,
            text=True,
            timeout=5,
            cwd="/home/user",
        )
    except subprocess.TimeoutExpired:
        pytest.fail("validate.py timed out. The infinite loop for n <= 0 has not been fixed.")

    assert result.returncode == 0, (
        f"validate.py failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_math_service_logic_directly():
    """Independently exercise fixed and unpredictable non-positive inputs."""
    service_path = "/home/user/math_service.py"
    assert os.path.isfile(service_path), f"Math service source is missing at {service_path}"

    negatives = [-17, -99]
    negatives.extend(-secrets.randbelow(2**63 - 1) - 1 for _ in range(24))
    for _ in range(12):
        bits = 65 + secrets.randbelow(1984)
        negatives.append(-(secrets.randbits(bits) | (1 << (bits - 1))))

    cases = [0] + negatives
    runner = r'''
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("submitted_math_service", "/home/user/math_service.py")
if spec is None or spec.loader is None:
    raise AssertionError("Could not load math_service.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert callable(getattr(module, "compute_collatz", None)), "compute_collatz is missing or not callable"
assert module.compute_collatz(10) == [10, 5, 16, 8, 4, 2, 1], "Failed normal case 10"
assert module.compute_collatz(1) == [1], "Failed base case 1"
for n in json.load(sys.stdin):
    result = module.compute_collatz(n)
    assert result == [], f"compute_collatz({n}) returned {result!r}, expected []"
'''

    try:
        result = subprocess.run(
            [sys.executable, "-c", runner],
            input=json.dumps(cases),
            capture_output=True,
            text=True,
            timeout=8,
            cwd="/tmp",
        )
    except subprocess.TimeoutExpired:
        pytest.fail("compute_collatz timed out on a non-positive integer.")

    assert result.returncode == 0, (
        "Independent compute_collatz checks failed.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
