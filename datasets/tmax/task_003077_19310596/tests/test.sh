#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile

import pytest
from scapy.all import Ether, IP, ICMP, UDP, Raw, wrpcap

SOURCE = "/home/user/analyzer.c"
PCAP = "/home/user/traffic.pcap"
LOG = "/home/user/fixed_output.log"
BINARY = "/tmp/analyzer_verifier"


def run_analyzer(timeout=5):
    try:
        result = subprocess.run(
            [BINARY],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The compiled analyzer hung, indicating the deadlock is still present.")
    assert result.returncode == 0, (
        f"The compiled analyzer exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    return result.stdout


@pytest.fixture(scope="session", autouse=True)
def compile_submission():
    assert os.path.exists(SOURCE), f"File {SOURCE} is missing."
    result = subprocess.run(
        ["gcc", "-O0", "-o", BINARY, SOURCE, "-lpcap", "-lpthread"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    assert result.returncode == 0, f"analyzer.c does not compile: {result.stderr}"
    assert os.path.isfile(BINARY), "Compilation did not produce an executable analyzer."


def test_fixed_output_log_exists():
    """Test that the fixed output log file exists."""
    assert os.path.exists(LOG), f"File {LOG} is missing. Ensure you redirected the output."
    assert os.path.isfile(LOG), f"{LOG} is not a file."


def test_fixed_output_log_content():
    """Test that the fixed output log contains the correct execution trace."""
    with open(LOG, "r") as f:
        content = f.read().strip()
        lines = content.split('\n')

    assert len(lines) > 0, f"File {LOG} is empty."
    assert any("Special ICMP packet detected!" in line for line in lines), \
        "The special ICMP packet was not detected in the log. Did the program process all packets?"

    last_line = lines[-1]
    assert "Total ICMP packets processed: 2" in last_line, \
        f"Expected the last line to be 'Total ICMP packets processed: 2', but got: '{last_line}'. " \
        "Ensure the deadlock is fixed and all packets are processed."


def test_analyzer_c_fixed():
    """Test that analyzer.c still uses mutexes but fixes the deadlock."""
    assert os.path.exists(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "pthread_mutex_lock(&log_lock);" in content, \
        "Do not remove the pthread_mutex_lock entirely. Fix the specific deadlock issue."
    assert "pthread_mutex_unlock(&log_lock);" in content, \
        "Missing pthread_mutex_unlock. Ensure you unlock the mutex before returning."


def test_compiled_analyzer_finishes_and_matches_log():
    """Execute the submitted source on the supplied capture and validate the saved run."""
    output = run_analyzer()
    lines = output.strip().splitlines()
    assert lines, "The compiled analyzer produced no output."
    assert any(line == "Special ICMP packet detected!" for line in lines), \
        "The compiled analyzer did not detect the special packet."
    assert lines[-1] == "Total ICMP packets processed: 2", \
        f"Unexpected final output from compiled analyzer: {lines[-1]!r}"

    with open(LOG, "r") as f:
        saved_lines = f.read().strip().splitlines()

    # Stats lines can vary with thread scheduling; all deterministic packet and
    # completion output must match the freshly executed program.
    saved_stable = [line for line in saved_lines if not line.startswith("Stats:")]
    actual_stable = [line for line in lines if not line.startswith("Stats:")]
    assert saved_stable == actual_stable, \
        "fixed_output.log is not the complete output of the submitted analyzer on traffic.pcap."


def test_compiled_analyzer_on_generated_capture():
    """Exercise the analyzer on verifier-generated traffic with derived answers."""
    rng = random.SystemRandom()
    normal_count = rng.randint(2, 5)
    special_count = rng.randint(1, 3)

    packets = []
    normal_sizes = [n for n in range(5, 80) if n != 56]
    for _ in range(normal_count):
        payload_size = rng.choice(normal_sizes)
        packets.append(Ether()/IP(dst="192.0.2.1")/ICMP()/Raw(os.urandom(payload_size)))
    for _ in range(special_count):
        # Ethernet + IPv4 + ICMP + 56 payload bytes is exactly 98 bytes.
        packets.append(Ether()/IP(dst="198.51.100.1")/ICMP()/Raw(os.urandom(56)))
    packets.append(Ether()/IP(dst="203.0.113.1")/UDP()/Raw(os.urandom(17)))
    rng.shuffle(packets)

    fd, backup = tempfile.mkstemp(prefix="traffic-backup-", suffix=".pcap")
    os.close(fd)
    shutil.copy2(PCAP, backup)
    try:
        wrpcap(PCAP, packets)
        output = run_analyzer()
    finally:
        shutil.copy2(backup, PCAP)
        os.unlink(backup)

    lines = output.strip().splitlines()
    assert lines, "The analyzer produced no output for generated traffic."
    assert sum(line == "Special ICMP packet detected!" for line in lines) == special_count, \
        "The analyzer did not process every generated special ICMP packet."
    assert lines[-1] == f"Total ICMP packets processed: {normal_count}", \
        f"Expected {normal_count} processed ICMP packets, got final line {lines[-1]!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
