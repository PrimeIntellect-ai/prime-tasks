#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest scapy

    mkdir -p /app/vendored
    mkdir -p /app/dumps
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Download and extract dpkt-1.9.8
    wget -qO dpkt-1.9.8.tar.gz https://pypi.io/packages/source/d/dpkt/dpkt-1.9.8.tar.gz
    tar -xzf dpkt-1.9.8.tar.gz -C /app/vendored
    rm dpkt-1.9.8.tar.gz

    # Apply the perturbation
    sed -i '/self.sum =/a \        self.sum = float("nan")' /app/vendored/dpkt-1.9.8/dpkt/ip.py

    # Generate crash.bin and PCAP files
    python3 -c "
import os
import random
from scapy.all import wrpcap, Ether, IP, TCP

# Generate crash.bin
with open('/app/dumps/crash.bin', 'wb') as f:
    f.write(os.urandom(5 * 1024 * 1024))
    f.write(b'Exception in module dpkt: NaN encountered during flow aggregation. Payload segment: X-MALFORMED-FLOW-TRIGGER-9941')
    f.write(os.urandom(5 * 1024 * 1024))

# Generate clean pcaps
for i in range(50):
    pkt = Ether()/IP(dst='192.168.1.1')/TCP(dport=80)/b'Normal payload data'
    wrpcap(f'/app/corpora/clean/clean_{i}.pcap', [pkt])

# Generate evil pcaps
for i in range(50):
    pkt = Ether()/IP(dst='192.168.1.1')/TCP(dport=80)/b'Prefix X-MALFORMED-FLOW-TRIGGER-9941 Suffix'
    wrpcap(f'/app/corpora/evil/evil_{i}.pcap', [pkt])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
