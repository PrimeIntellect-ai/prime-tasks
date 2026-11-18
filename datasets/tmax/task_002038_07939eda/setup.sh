#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest scapy

mkdir -p /home/user/sensor_aggregator
cd /home/user/sensor_aggregator
git init

export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test User"
export GIT_COMMITTER_EMAIL="test@example.com"

cat << 'EOF' > aggregate.py
import struct
import sys

def process_payload(data):
    if len(data) < 12: return 0.0
    sensor_id, v1, v2 = struct.unpack('<Iff', data[:12])
    return (v1 + v2) / 2.0

if __name__ == "__main__":
    if len(sys.argv) > 1:
        payload = bytes.fromhex(sys.argv[1])
        print(process_payload(payload))
EOF

git add aggregate.py
git commit -m "Initial commit"
git tag v1.0

for i in {1..100}; do
    echo "# dummy $i" >> aggregate.py
    git commit -am "Dummy commit $i"
done

cat << 'EOF' > aggregate.py
import struct
import math
import sys

def process_payload(data):
    if len(data) < 12: return 0.0
    sensor_id, v1, v2 = struct.unpack('<Iff', data[:12])
    mean = (v1 + v2) / 2.0
    variance = ((v1 - mean)**2 + (v2 - mean)**2) / 2.0
    # Numerical instability here:
    normalized = mean / math.sqrt(variance)
    return normalized

if __name__ == "__main__":
    if len(sys.argv) > 1:
        payload = bytes.fromhex(sys.argv[1])
        print(process_payload(payload))
EOF
git commit -am "Add normalization based on variance"

for i in {101..150}; do
    echo "# dummy $i" >> aggregate.py
    git commit -am "Dummy commit $i"
done

cd /home/user
cat << 'EOF' > make_pcap.py
from scapy.all import *
import struct

# Normal packet
p1 = IP(dst="127.0.0.1")/UDP(dport=5000)/struct.pack('<Iff', 1, 10.0, 20.0)
# Poison packet (v1 == v2 causes variance = 0)
p2 = IP(dst="127.0.0.1")/UDP(dport=5000)/struct.pack('<Iff', 2, 15.5, 15.5)
# Normal packet
p3 = IP(dst="127.0.0.1")/UDP(dport=5000)/struct.pack('<Iff', 3, 5.0, 8.0)

wrpcap('traffic.pcap', [p1, p2, p3])
EOF

python3 make_pcap.py
rm make_pcap.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
