#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import os
from pathlib import Path
import random
import secrets
import stat
import struct
import subprocess
import sys

from scapy.all import Ether, IP, UDP, Raw, wrpcap

ROOT = Path("/home/user/uptime_monitor")
SCRIPT = ROOT / "process_heartbeats.py"
PCAP = ROOT / "data/heartbeats.pcap"
OUTPUT = ROOT / "max_timestamp.txt"
ORIGINAL_SECRET = "SRE_MONITOR_K3Y_99"


def run_processor(secret):
    env = os.environ.copy()
    env["HEARTBEAT_SECRET"] = secret
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def assert_output(expected):
    assert OUTPUT.is_file(), f"Output file {OUTPUT} does not exist after running the script."
    content = OUTPUT.read_text().strip()
    assert content == str(expected), f"Expected max timestamp to be {expected}, but got {content}"


def test_max_timestamp_file_exists_and_correct():
    path = "/home/user/uptime_monitor/max_timestamp.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist. Did you run the script?"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_value = "3000000000"
    assert content == expected_value, f"Expected max timestamp to be {expected_value}, but got {content}"


def test_process_heartbeats_script_fixed():
    path = "/home/user/uptime_monitor/process_heartbeats.py"
    assert os.path.isfile(path), f"Python script {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    assert "struct.unpack('>I'" in content or "struct.unpack(\">I\"" in content or "struct.unpack( '>I'" in content, \
        "The script does not appear to use the correct unsigned integer format (>I) for unpacking the timestamp."
    assert "struct.unpack('>i'" not in content, \
        "The script still contains the buggy signed integer format (>i)."


def test_script_is_regular_file_and_processes_original_capture():
    assert SCRIPT.exists(), f"Python script {SCRIPT} does not exist."
    assert not SCRIPT.is_symlink(), "process_heartbeats.py must be a real file, not a symlink."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), "process_heartbeats.py is not a regular file."
    assert PCAP.is_file(), f"Capture file {PCAP} does not exist."

    OUTPUT.unlink(missing_ok=True)
    result = run_processor(ORIGINAL_SECRET)
    assert result.returncode == 0, (
        f"Processor failed on the supplied capture (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_output(3000000000)


def test_processor_parses_unsigned_timestamps_and_verifies_hmac():
    original_pcap = PCAP.read_bytes()
    dynamic_secret = "verifier_" + secrets.token_hex(24)
    key = dynamic_secret.encode()

    valid_timestamps = [
        random.SystemRandom().randrange(500000000, 1800000000),
        random.SystemRandom().randrange(2147483648, 2990000000),
        random.SystemRandom().randrange(3010000000, 4200000000),
    ]
    expected = max(valid_timestamps)
    packets = []

    for index, timestamp in enumerate(valid_timestamps, start=501):
        node_id = struct.pack(">I", index)
        timestamp_bytes = struct.pack(">I", timestamp)
        mac = hmac.new(key, node_id + timestamp_bytes, hashlib.sha256).digest()[:16]
        payload = node_id + timestamp_bytes + mac
        packets.append(Ether()/IP(dst="192.168.1.100")/UDP(dport=8080)/Raw(payload))

    # A larger timestamp with a deliberately invalid MAC must not affect the result.
    bad_node = struct.pack(">I", 999)
    bad_timestamp = struct.pack(">I", 4294967294)
    genuine_mac = hmac.new(key, bad_node + bad_timestamp, hashlib.sha256).digest()[:16]
    bad_mac = bytes([genuine_mac[0] ^ 1]) + genuine_mac[1:]
    packets.append(Ether()/IP(dst="192.168.1.100")/UDP(dport=8080)/Raw(bad_node + bad_timestamp + bad_mac))
    random.SystemRandom().shuffle(packets)

    try:
        wrpcap(str(PCAP), packets)
        OUTPUT.unlink(missing_ok=True)
        result = run_processor(dynamic_secret)
        assert result.returncode == 0, (
            f"Processor failed on generated capture (exit {result.returncode}).\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert_output(expected)
    finally:
        PCAP.write_bytes(original_pcap)
        OUTPUT.unlink(missing_ok=True)
        restore = run_processor(ORIGINAL_SECRET)
        assert restore.returncode == 0, (
            "Processor could not regenerate the required final output after testing.\n"
            f"stdout:\n{restore.stdout}\nstderr:\n{restore.stderr}"
        )
        assert_output(3000000000)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
