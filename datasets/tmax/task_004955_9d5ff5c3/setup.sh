#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest dpkt scapy

    mkdir -p /home/user/uptime_monitor/data
    cd /home/user/uptime_monitor

    # Generate the PCAP file
    cat << 'EOF' > generate_pcap.py
from scapy.all import Ether, IP, UDP, wrpcap
import struct
import hmac
import hashlib

secret = b"SRE_MONITOR_K3Y_99"
packets = []
timestamps = [1000000000, 2000000000, 2500000000, 3000000000]

for ts in timestamps:
    node_id = struct.pack('>I', 101)
    ts_bytes = struct.pack('>I', ts)
    mac = hmac.new(secret, node_id + ts_bytes, hashlib.sha256).digest()[:16]
    payload = node_id + ts_bytes + mac

    pkt = Ether()/IP(dst="192.168.1.100")/UDP(dport=8080)/payload
    packets.append(pkt)

wrpcap("data/heartbeats.pcap", packets)
EOF
    python3 generate_pcap.py
    rm generate_pcap.py

    # Setup Git Repo
    git init
    git config user.email "sre@example.com"
    git config user.name "SRE"

    # Commit 1: Hardcoded secret
    cat << 'EOF' > config.json
{
    "secret": "SRE_MONITOR_K3Y_99"
}
EOF
    git add config.json
    git commit -m "Initial commit with config"

    # Commit 2: Remove secret
    rm config.json
    git add config.json
    git commit -m "Security: Remove hardcoded secret"

    # Commit 3: Add buggy script
    cat << 'EOF' > process_heartbeats.py
import dpkt
import struct
import hmac
import hashlib
import os

secret = os.environ.get("HEARTBEAT_SECRET", "").encode()
if not secret:
    print("Error: Missing HEARTBEAT_SECRET environment variable.")
    exit(1)

max_ts = 0
with open("data/heartbeats.pcap", "rb") as f:
    pcap = dpkt.pcap.Reader(f)
    for ts, buf in pcap:
        eth = dpkt.ethernet.Ethernet(buf)
        ip = eth.data
        udp = ip.data
        payload = udp.data

        node_id = payload[0:4]
        timestamp_bytes = payload[4:8]
        mac = payload[8:]

        expected_mac = hmac.new(secret, node_id + timestamp_bytes, hashlib.sha256).digest()[:16]
        if mac != expected_mac:
            continue # Invalid MAC

        # BUG: unpacking as signed integer (>i) instead of unsigned (>I)
        extracted_ts = struct.unpack('>i', timestamp_bytes)[0]

        if extracted_ts < 0:
            raise ValueError(f"Negative timestamp detected! {extracted_ts}")

        if extracted_ts > max_ts:
            max_ts = extracted_ts

with open("max_timestamp.txt", "w") as f:
    f.write(str(max_ts))
EOF
    git add process_heartbeats.py data/heartbeats.pcap
    git commit -m "Add heartbeat processor and data"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
