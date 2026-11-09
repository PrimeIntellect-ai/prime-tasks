#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tcpdump tshark
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import scapy.all as scapy
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.l2 import Ether

def setup_environment():
    p1 = Ether()/IP(dst="192.168.1.100")/TCP(dport=80)/b"GET / HTTP/1.1\r\n\r\n"
    payload = b'{"op": "multiply", "args": [18446744073709551616, 55'
    p2 = Ether()/IP(dst="192.168.1.100")/TCP(dport=9000)/payload
    p3 = Ether()/IP(dst="192.168.1.100")/UDP(dport=53)/b"dns query"
    scapy.wrpcap("/home/user/capture.pcap", [p1, p2, p3])

setup_environment()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
