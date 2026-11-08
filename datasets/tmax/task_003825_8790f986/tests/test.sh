#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
from scapy.utils import PcapReader


def test_solution_file():
    sol_path = "/home/user/solution.txt"
    pcap_path = "/home/user/service/test_traffic.pcap"

    assert os.path.exists(sol_path), f"Solution file {sol_path} does not exist."
    assert os.path.exists(pcap_path), f"Packet capture {pcap_path} does not exist."

    with open(sol_path, "r") as f:
        sol_content = f.read().strip()

    lengths = []
    with PcapReader(pcap_path) as pcap_reader:
        for packet in pcap_reader:
            lengths.append(len(packet))

    mean = sum(lengths) / len(lengths)
    variance = sum((value - mean) ** 2 for value in lengths) / len(lengths)
    exp_content = f"{variance:.4f}"

    assert sol_content == exp_content, f"Expected variance {exp_content}, but got {sol_content} in {sol_path}."


def test_memory_leak_fixed():
    script_path = "/home/user/service/packet_processor.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "self.history.append" not in content, "Memory leak still present: self.history.append is still in packet_processor.py"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
