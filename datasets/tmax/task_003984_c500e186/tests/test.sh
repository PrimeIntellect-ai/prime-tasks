#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest
from scapy.all import Ether, IP, TCP, UDP, ICMP, PcapReader, wrpcap

APP_DIR = "/home/user/app"
BINARY = os.path.join(APP_DIR, "packet_processor")
MAKEFILE = os.path.join(APP_DIR, "Makefile")
SOURCE = os.path.join(APP_DIR, "packet_processor.c")
RESULT = "/home/user/result.txt"
PRODUCTION_PCAP = "/home/user/data/traffic.pcap"


def run_processor(pcap_path, timeout=8):
    try:
        completed = subprocess.run(
            [BINARY, pcap_path],
            cwd=APP_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("packet_processor did not terminate; the deadlock is still present")

    assert completed.returncode == 0, (
        f"packet_processor exited with {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout


def parse_output(output):
    match = re.fullmatch(
        r"\s*TCP packets:\s*(\d+)\s*\n"
        r"UDP packets:\s*(\d+)\s*\n"
        r"Total processed:\s*(\d+)\s*",
        output,
    )
    assert match, f"Unexpected packet_processor output format: {output!r}"
    return tuple(int(value) for value in match.groups())


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert os.path.isfile(MAKEFILE), "Makefile is missing"
    assert os.path.isfile(SOURCE), "packet_processor.c is missing"

    with open(MAKEFILE, "r") as f:
        makefile_text = f.read()
    assert re.search(r"(?<![A-Za-z0-9_])-pthread(?![A-Za-z0-9_])", makefile_text), (
        "Makefile does not contain the required -pthread flag"
    )
    assert re.search(r"(?<![A-Za-z0-9_])-lpcap(?![A-Za-z0-9_])", makefile_text), (
        "Makefile does not contain the required -lpcap flag"
    )

    if os.path.lexists(BINARY):
        os.remove(BINARY)
    try:
        completed = subprocess.run(
            ["make", "-B"],
            cwd=APP_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("make did not complete")

    assert completed.returncode == 0, f"make failed:\n{completed.stdout}"
    assert os.path.isfile(BINARY), "make did not create packet_processor"
    assert os.access(BINARY, os.X_OK), "packet_processor is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "packet_processor is not a compiled ELF executable"


def test_result_file_exists():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Expected result file {result_path} does not exist. Did you run the program and redirect stdout?"


def test_result_file_content():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), "Result file missing."

    with open(result_path, "r") as f:
        content = f.read()

    assert re.search(r"TCP packets:\s*150", content), "TCP packets count is incorrect or missing in result.txt. Expected 150."
    assert re.search(r"UDP packets:\s*85", content), "UDP packets count is incorrect or missing in result.txt. Expected 85."
    assert re.search(r"Total processed:\s*235", content), "Total processed count is incorrect or missing in result.txt. Expected 235."


def test_result_matches_built_program_on_production_capture():
    actual_stdout = run_processor(PRODUCTION_PCAP)
    with open(RESULT, "r") as f:
        saved_result = f.read()
    assert actual_stdout.strip() == saved_result.strip(), (
        "result.txt is not the output of the built packet_processor on traffic.pcap"
    )
    assert parse_output(actual_stdout) == (150, 85, 235)


def test_dynamic_high_contention_capture_completes_and_counts_packets():
    tcp_requested = 600 + secrets.randbelow(251)
    udp_requested = 600 + secrets.randbelow(251)
    ignored_requested = 5 + secrets.randbelow(10)

    packets = []
    packets.extend(Ether()/IP(dst="10.10.0.1")/TCP(dport=443) for _ in range(tcp_requested))
    packets.extend(Ether()/IP(dst="10.10.0.2")/UDP(dport=5353) for _ in range(udp_requested))
    packets.extend(Ether()/IP(dst="10.10.0.3")/ICMP() for _ in range(ignored_requested))

    with tempfile.NamedTemporaryFile(suffix=".pcap", delete=False) as tmp:
        test_pcap = tmp.name
    try:
        wrpcap(test_pcap, packets)

        expected_tcp = 0
        expected_udp = 0
        with PcapReader(test_pcap) as reader:
            for packet in reader:
                if packet.haslayer(IP):
                    if int(packet[IP].proto) == 6:
                        expected_tcp += 1
                    elif int(packet[IP].proto) == 17:
                        expected_udp += 1
        expected = (expected_tcp, expected_udp, expected_tcp + expected_udp)

        # Repeated executions make the high-contention deadlock check robust.
        for _ in range(3):
            assert parse_output(run_processor(test_pcap)) == expected
    finally:
        if os.path.exists(test_pcap):
            os.remove(test_pcap)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
