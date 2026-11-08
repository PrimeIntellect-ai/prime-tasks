#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import sys

import pytest
from scapy.all import IP, TCP, rdpcap, wrpcap

FIXED = "/home/user/network_parser_fixed.py"
CAPTURE = "/home/user/capture.pcap"


def run_parser(pcap_path):
    try:
        return subprocess.run(
            [sys.executable, FIXED, pcap_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Executing {FIXED} failed with return code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Executing {FIXED} timed out.")


def test_leak_packet_identified():
    file_path = "/home/user/leak_packet.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "73", f"Expected packet number 73 in {file_path}, but got '{content}'."


def test_network_parser_fixed_exists():
    assert os.path.isfile(FIXED), f"Fixed script {FIXED} does not exist."


def test_network_parser_fixed_execution():
    assert os.path.isfile(FIXED), f"Fixed script {FIXED} does not exist."
    assert os.path.isfile(CAPTURE), f"PCAP file {CAPTURE} does not exist."
    result = run_parser(CAPTURE)
    assert "Leaked buffer items: 0" in result.stdout, (
        f"Expected 'Leaked buffer items: 0' in output, but got:\n{result.stdout}"
    )


def test_fixed_parser_retains_session_tracking_and_drops_orphans(tmp_path):
    # Generate an unpredictable capture after the agent has finished. Expected
    # session state is derived from the packets written, rather than from the
    # parser's self-reported summary.
    token = secrets.randbelow(200) + 20
    packets = []
    session_specs = []

    for i in range(4 + secrets.randbelow(4)):
        src = f"172.{token % 250}.{i + 1}.{10 + i}"
        dst = f"10.{(token + i) % 250}.0.{20 + i}"
        sport = 20000 + token * 10 + i
        dport = 8000 + i
        key = f"{src}:{sport}-{dst}:{dport}"
        packets.append(IP(src=src, dst=dst) / TCP(sport=sport, dport=dport, flags="S"))
        payload_count = 1 + secrets.randbelow(3)
        payload_indices = []
        for j in range(payload_count):
            payload_indices.append(len(packets))
            payload = secrets.token_bytes(5 + j * 7)
            packets.append(
                IP(src=src, dst=dst)
                / TCP(sport=sport, dport=dport, flags="PA")
                / payload
            )
        session_specs.append((key, payload_indices))

    # Orphan PA packets are ignored normally, and orphan UPA packets are the
    # malformed trigger. Neither may alter valid session state or be retained.
    for i in range(80):
        src = f"198.18.{i // 250}.{(i % 250) + 1}"
        flags = "UPA" if i % 2 == 0 else "PA"
        packets.append(
            IP(src=src, dst="203.0.113.9")
            / TCP(sport=30000 + i, dport=443, flags=flags)
            / secrets.token_bytes(3 + (i % 11))
        )

    pcap = tmp_path / "derived_case.pcap"
    wrpcap(str(pcap), packets)
    reread = rdpcap(str(pcap))
    expected = {
        key: [len(reread[index]) for index in payload_indices]
        for key, payload_indices in session_specs
    }

    # Exercise the submitted artifact through its command-line interface on the
    # independently generated input as well as on the supplied capture.
    result = run_parser(str(pcap))
    assert re.search(r"^Leaked buffer items:\s*0\s*$", result.stdout, re.MULTILINE), result.stdout

    expected_file = tmp_path / "expected.json"
    expected_file.write_text(json.dumps(expected))
    probe = tmp_path / "probe.py"
    probe.write_text(r'''
import contextlib
import importlib.util
import io
import json
import sys

script, pcap, expected_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("submitted_network_parser", script)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, "SessionTracker"), "fixed script does not provide SessionTracker"
tracker = module.SessionTracker()

class RejectingOrphanBuffer(list):
    def append(self, item):
        raise AssertionError("malformed orphan packet was retained")

if hasattr(tracker, "orphan_buffer"):
    tracker.orphan_buffer = RejectingOrphanBuffer()

with contextlib.redirect_stdout(io.StringIO()):
    tracker.process_pcap(pcap)

expected = json.load(open(expected_path))
assert hasattr(tracker, "sessions"), "tracker has no session state"
assert tracker.sessions == expected, f"session state mismatch: {tracker.sessions!r} != {expected!r}"
if hasattr(tracker, "orphan_buffer"):
    assert len(tracker.orphan_buffer) == 0, "orphan packets remain buffered"
print("STATE_OK")
''')

    try:
        checked = subprocess.run(
            [sys.executable, str(probe), FIXED, str(pcap), str(expected_file)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Session-state probe failed.\nStdout: {e.stdout}\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Session-state probe timed out.")
    assert "STATE_OK" in checked.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
