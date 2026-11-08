#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import random
import subprocess
import hashlib
import pytest

def create_pcap(filename, num_packets):
    with open(filename, 'wb') as f:
        # PCAP Global header (little-endian)
        # magic_number, version_major, version_minor, thiszone, sigfigs, snaplen, network (1 = Ethernet)
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        for _ in range(num_packets):
            payload_len = random.randint(1, 1472)
            payload = os.urandom(payload_len)

            # UDP Header
            src_port = random.randint(1024, 65535)
            dst_port = 8080 if random.random() < 0.7 else random.randint(1024, 65535)
            udp_len = 8 + payload_len
            udp_hdr = struct.pack('!HHHH', src_port, dst_port, udp_len, 0)

            # IPv4 Header
            ip_len = 20 + udp_len
            ip_hdr = struct.pack('!BBHHHBBHII', 0x45, 0, ip_len, 0, 0, 64, 17, 0, 0x01020304, 0x05060708)

            # Ethernet Header
            eth_hdr = struct.pack('!6s6sH', b'\x00'*6, b'\x00'*6, 0x0800)

            packet = eth_hdr + ip_hdr + udp_hdr + payload

            # Packet Header (little-endian)
            incl_len = len(packet)
            orig_len = len(packet)
            f.write(struct.pack('<IIII', 0, 0, incl_len, orig_len))
            f.write(packet)

def get_file_hash(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

def test_pcap_extractor_fuzz_equivalence():
    agent_binary = "/home/user/repo/pcap-extractor"
    oracle_binary = "/tests/pcap-extractor-oracle"

    assert os.path.isfile(agent_binary), f"Agent binary not found at {agent_binary}"
    assert os.access(agent_binary, os.X_OK), f"Agent binary {agent_binary} is not executable"

    assert os.path.isfile(oracle_binary), f"Oracle binary not found at {oracle_binary}"
    assert os.access(oracle_binary, os.X_OK), f"Oracle binary {oracle_binary} is not executable"

    random.seed(42)
    num_tests = 100

    for i in range(num_tests):
        pcap_file = f"/tmp/fuzz_{i}.pcap"
        oracle_out = f"/tmp/oracle_out_{i}.bin"
        agent_out = f"/tmp/agent_out_{i}.bin"

        num_packets = random.randint(10, 100)
        create_pcap(pcap_file, num_packets)

        # Run Oracle
        oracle_proc = subprocess.run(
            [oracle_binary, "8080", pcap_file, oracle_out],
            capture_output=True
        )

        # Run Agent
        agent_proc = subprocess.run(
            [agent_binary, "8080", pcap_file, agent_out],
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Exit code mismatch on input {pcap_file}. "
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
        )

        oracle_hash = get_file_hash(oracle_out)
        agent_hash = get_file_hash(agent_out)

        assert oracle_hash == agent_hash, (
            f"Output file mismatch on input {pcap_file}.\n"
            f"Oracle hash: {oracle_hash}\n"
            f"Agent hash:  {agent_hash}\n"
            "The extractor is likely still dropping bytes or extracting incorrectly."
        )

        # Cleanup
        os.remove(pcap_file)
        if os.path.exists(oracle_out): os.remove(oracle_out)
        if os.path.exists(agent_out): os.remove(agent_out)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
