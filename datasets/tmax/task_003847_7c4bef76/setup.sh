#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    mkdir -p /home/user/simulation_build
    cd /home/user/simulation_build

    cat << 'EOF' > math_engine.py
import math

def compute_trajectory(payload_dict):
    x = payload_dict.get('x', 0.0)
    y = payload_dict.get('y', 0.0)
    z = payload_dict.get('z', 0.0)

    # Complex numerical calculation
    denominator = (x**2 + y**2 - z**2)

    # Bug: susceptible to division by zero if x^2 + y^2 == z^2
    result = 100.0 / denominator
    return result
EOF

    cat << 'EOF' > generate_pcap.py
from scapy.all import *
import json

packets = []
payloads = [
    {"x": 1.0, "y": 2.0, "z": 1.0},
    {"x": 5.0, "y": 1.2, "z": 2.5},
    {"x": 3.0, "y": 4.0, "z": 5.0},  # Problematic: 9 + 16 - 25 = 0
    {"x": 7.0, "y": 8.0, "z": 9.0}
]

for i, p in enumerate(payloads):
    pkt = IP(dst="127.0.0.1")/UDP(dport=9000, sport=12345)/Raw(load=json.dumps(p).encode('utf-8'))
    packets.append(pkt)

# Add some noise traffic
noise_pkt = IP(dst="127.0.0.1")/TCP(dport=80)/Raw(load=b"GET / HTTP/1.1\r\n\r\n")
packets.insert(1, noise_pkt)

wrpcap('traffic_capture.pcap', packets)
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
