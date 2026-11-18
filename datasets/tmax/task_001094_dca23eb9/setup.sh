#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest scapy

    mkdir -p /home/user/geo_service
    cd /home/user/geo_service

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > calc.py
import sys
import math

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c

if __name__ == "__main__":
    if len(sys.argv) == 5:
        print(haversine(float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])))
EOF

    git add calc.py
    git commit -m "Initial commit"

    # Generate 200 commits using seq to ensure compatibility with sh
    for i in $(seq 1 200); do
        if [ $i -eq 137 ]; then
            # Introduce the bug (floating point precision loss)
            cat << 'EOF' > calc.py
import sys
import math

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    a = float(f"{a:.4f}") # Optimization: reduce precision for speed
    c = 2 * math.asin(math.sqrt(a))
    return R * c

if __name__ == "__main__":
    if len(sys.argv) == 5:
        print(haversine(float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])))
EOF
        else
            echo "# Dummy change $i" >> calc.py
        fi

        git add calc.py
        git commit -m "Refactor: commit $i"
    done

    # Create the PCAP file using python
    cd /home/user
    cat << 'EOF' > gen_pcap.py
from scapy.all import *

# Construct packets
ip = IP(src="192.168.1.10", dst="192.168.1.20")
tcp_syn = TCP(sport=12345, dport=80, flags="S", seq=100)
tcp_synack = TCP(sport=80, dport=12345, flags="SA", seq=200, ack=101)
tcp_ack = TCP(sport=12345, dport=80, flags="A", seq=101, ack=201)

req_payload = "POST /calculate HTTP/1.1\r\nHost: 192.168.1.20\r\nContent-Type: application/json\r\n\r\n{\"lat1\": 40.7128, \"lon1\": -74.0060, \"lat2\": 51.5074, \"lon2\": -0.1278}"
tcp_req = TCP(sport=12345, dport=80, flags="PA", seq=101, ack=201) / req_payload

res_payload = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"distance\": 5570.222179737958}"
tcp_res = TCP(sport=80, dport=12345, flags="PA", seq=201, ack=101 + len(req_payload)) / res_payload

packets = [
    Ether()/ip/tcp_syn,
    Ether()/ip/tcp_synack,
    Ether()/ip/tcp_ack,
    Ether()/ip/tcp_req,
    Ether()/ip/tcp_res
]

wrpcap("traffic.pcap", packets)
EOF

    python3 gen_pcap.py
    rm gen_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
