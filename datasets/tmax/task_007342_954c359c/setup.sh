#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump strace
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
import socket
import ctypes
import sys

def process_request(data):
    if len(data) > 4 and b"CRASH" in data:
        # Trigger a segmentation fault by dereferencing a null pointer
        ctypes.string_at(0)
    return b"PONG\n"

def start_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(5)

    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if not data:
            break
        response = process_request(data)
        conn.send(response)
        conn.close()

if __name__ == "__main__":
    start_server()
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import *

packets = []

# Normal traffic
packets.append(IP(src="192.168.1.10", dst="10.0.0.5")/TCP(sport=12345, dport=8888)/Raw(load=b"PING"))
packets.append(IP(src="192.168.1.11", dst="10.0.0.5")/TCP(sport=12346, dport=8888)/Raw(load=b"PING"))
packets.append(IP(src="192.168.1.12", dst="10.0.0.5")/TCP(sport=12347, dport=8888)/Raw(load=b"HELO"))

# Anomalous traffic causing the crash
packets.append(IP(src="172.16.45.99", dst="10.0.0.5")/TCP(sport=55555, dport=8888)/Raw(load=b"CRASH_ME_NOW"))

# More normal traffic
packets.append(IP(src="192.168.1.10", dst="10.0.0.5")/TCP(sport=12348, dport=8888)/Raw(load=b"PING"))

wrpcap("/home/user/traffic.pcap", packets)
EOF

    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    chmod -R 777 /home/user
