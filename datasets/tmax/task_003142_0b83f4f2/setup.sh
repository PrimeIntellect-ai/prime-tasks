#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create the transformation script
    cat << 'EOF' > transform.py
import sys
import json
import struct

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        # Simulate legacy 32-bit float C-struct transformation precision loss
        val_32 = struct.unpack('f', struct.pack('f', data['value']))[0]
        data['value'] = val_32
        print(json.dumps(data))
    except Exception as e:
        pass
EOF
    chmod +x transform.py

    # Generate the pcap file using python
    cat << 'EOF' > generate_pcap.py
from scapy.all import *
import json

packets = []
# BETA-02 has a large value that cannot be represented exactly in a 32-bit float, causing precision loss > 0.001
# 9876543.21 in 32-bit float becomes 9876543.0, diff is 0.21
data = [
    {"sensor_id": "ALPHA-01", "value": 12.345},
    {"sensor_id": "BETA-02", "value": 9876543.21},
    {"sensor_id": "GAMMA-03", "value": 100.0625},
    {"sensor_id": "DELTA-04", "value": -0.00012345}
]

for d in data:
    payload = json.dumps(d).encode('utf-8') + b'\n'
    pkt = Ether()/IP(src="192.168.1.100", dst="10.0.0.5")/UDP(sport=12345, dport=5000)/payload
    packets.append(pkt)

wrpcap('traffic.pcap', packets)
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    chmod -R 777 /home/user
