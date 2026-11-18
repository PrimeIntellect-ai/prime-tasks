#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest scapy

    mkdir -p /home/user

    # Create the Python script to setup the environment
    cat << 'EOF' > /tmp/setup.py
import os
import subprocess
import random
from scapy.all import *

# 1. Setup Git Repo
repo_dir = "/home/user/repo"
os.makedirs(repo_dir, exist_ok=True)
os.chdir(repo_dir)

subprocess.run(["git", "init"], check=True)
subprocess.run(["git", "config", "user.name", "Test User"], check=True)
subprocess.run(["git", "config", "user.email", "test@example.com"], check=True)

good_code = """
def deserialize(payload: bytes):
    try:
        return payload.decode('utf-8', errors='ignore')
    except Exception as e:
        raise ValueError("Parse error")
"""

bad_code = """
def deserialize(payload: bytes):
    # Optimization: strict ascii decode for speed
    return payload.decode('ascii')
"""

bad_commit_index = 142
bad_commit_hash = ""

for i in range(200):
    if i < bad_commit_index:
        code = good_code
        msg = f"Commit {i}: Minor updates"
    elif i == bad_commit_index:
        code = bad_code
        msg = f"Commit {i}: Optimize decoding for speed"
    else:
        code = bad_code
        msg = f"Commit {i}: More features"

    with open("processor.py", "w") as f:
        f.write(code + f"\n# Dummy change {i}\n")

    subprocess.run(["git", "add", "processor.py"], check=True)
    subprocess.run(["git", "commit", "-m", msg], check=True)

    if i == bad_commit_index:
        res = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True)
        bad_commit_hash = res.stdout.strip()

with open("/tmp/truth_commit.txt", "w") as f:
    f.write(bad_commit_hash)

# 2. Setup PCAP
packets = []
packets.append(IP(dst="127.0.0.1")/TCP(dport=80)/Raw(load=b"GET / HTTP/1.1\r\n\r\n"))
packets.append(IP(dst="127.0.0.1")/TCP(dport=8888)/Raw(load=b"PING"))
malicious_payload = b"DATA:\xe2\x98\xa0\x00"
packets.append(IP(dst="127.0.0.1")/TCP(dport=8888)/Raw(load=malicious_payload))
packets.append(IP(dst="127.0.0.1")/TCP(dport=8888)/Raw(load=b"PONG"))

wrpcap("/home/user/traffic.pcap", packets)

# 3. Setup Memory Dump
dump_path = "/home/user/crash.dmp"
target_string = b"ERR_STATE_A9F3B2C1D4"

with open(dump_path, "wb") as f:
    f.write(os.urandom(1024 * 50))
    f.write(target_string)
    f.write(os.urandom(1024 * 50))
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
