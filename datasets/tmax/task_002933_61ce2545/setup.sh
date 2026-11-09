#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump xxd gawk
    pip3 install pytest scapy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
import time

pkts = []
# Packet 1
p1 = IP(dst="192.168.1.100")/TCP(dport=80)/Raw(load=b"X"*10)
p1.time = 1600000000.123456
pkts.append(p1)

# Packet 2
p2 = IP(dst="192.168.1.100")/TCP(dport=80)/Raw(load=b"Y"*10)
p2.time = 1600000001.000001
pkts.append(p2)

# Packet 3
p3 = IP(dst="192.168.1.100")/TCP(dport=80)/Raw(load=b"Z"*5)
p3.time = 1600000001.500000
pkts.append(p3)

# Packet 4
p4 = IP(dst="192.168.1.100")/TCP(dport=80)/Raw(load=b"W"*10)
p4.time = 1600000002.999999
pkts.append(p4)

wrpcap('/home/user/traffic.pcap', pkts)
EOF
    python3 /tmp/gen_pcap.py

    cat << 'EOF' > /home/user/dropper.sh
#!/bin/bash
# Suspicious dropper script

# Dump the packets
tcpdump -r /home/user/traffic.pcap -tttt -nn -x > /tmp/dump.txt 2>/dev/null

# Calculate key (Bug: awk floating point precision loss)
# Should be exactly 6400000005.623456 but default awk print drops precision
KEY=$(awk '/IP/ {sum += $1} END {print sum}' /tmp/dump.txt)

# Extract payload (Bug: doesn't handle the malformed packet indicator or specific length)
grep -v "IP" /tmp/dump.txt | awk '{for(i=1;i<=NF;i++) printf "%s", $i}' > /tmp/hex.txt

# Convert to binary
xxd -r -p /tmp/hex.txt > /home/user/payload.bin
EOF
    chmod +x /home/user/dropper.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
