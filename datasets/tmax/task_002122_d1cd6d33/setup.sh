#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo tcpdump tshark
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    # Create math_service.py
    cat << 'EOF' > /home/user/math_service.py
import json

def compute_collatz(n):
    assert isinstance(n, int), "Input must be an integer"
    seq = [n]
    # BUG: if n <= 0 (e.g., 0 or -5), this will loop infinitely
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        seq.append(n)
    return seq

def process_payload(payload_bytes):
    data = json.loads(payload_bytes.decode('utf-8'))
    return compute_collatz(data.get("value", 1))
EOF

    # Create validate.py
    cat << 'EOF' > /home/user/validate.py
from math_service import compute_collatz

def run_tests():
    # Normal cases
    assert compute_collatz(10) == [10, 5, 16, 8, 4, 2, 1], "Failed normal case 10"
    assert compute_collatz(1) == [1], "Failed base case 1"

    # Edge cases that used to fail
    assert compute_collatz(0) == [], "Failed edge case 0 (should return empty list)"
    assert compute_collatz(-17) == [], "Failed edge case -17 (should return empty list)"

    print("All assertions passed.")

if __name__ == "__main__":
    run_tests()
EOF

    # Create pcap generation script
    cat << 'EOF' > /tmp/generate_pcap.py
from scapy.all import IP, UDP, wrpcap, Ether
import json

packets = []
values_to_send = [15, 27, 9, 0] # 0 is the poison pill that causes infinite loop

for val in values_to_send:
    payload = json.dumps({"value": val}).encode('utf-8')
    # Create a dummy packet
    pkt = Ether()/IP(dst="127.0.0.1", src="127.0.0.1")/UDP(dport=8888, sport=12345)/payload
    packets.append(pkt)

wrpcap('/home/user/traffic.pcap', packets)
EOF

    # Generate the pcap
    python3 /tmp/generate_pcap.py
    rm /tmp/generate_pcap.py

    chmod -R 777 /home/user
