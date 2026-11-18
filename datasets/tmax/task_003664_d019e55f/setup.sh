#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/base_sshd_config
Port 22
ListenAddress 0.0.0.0
#PermitRootLogin prohibit-password
#PasswordAuthentication yes
X11Forwarding yes
#Protocol 2
EOF

    cat << 'EOF' > /tmp/setup_pcap.py
from scapy.all import *

encoded_payload = bytes([ord(c) ^ 0x55 for c in 'whoami'])

p1 = IP(src="10.13.37.100", dst="192.168.1.50")/TCP(sport=54321, dport=7777, flags="S", seq=1000)
p2 = IP(src="192.168.1.50", dst="10.13.37.100")/TCP(sport=7777, dport=54321, flags="SA", seq=2000, ack=1001)
p3 = IP(src="10.13.37.100", dst="192.168.1.50")/TCP(sport=54321, dport=7777, flags="A", seq=1001, ack=2001)
p4 = IP(src="10.13.37.100", dst="192.168.1.50")/TCP(sport=54321, dport=7777, flags="PA", seq=1001, ack=2001)/Raw(load=encoded_payload)

wrpcap('/home/user/capture.pcap', [p1, p2, p3, p4])
EOF

    python3 /tmp/setup_pcap.py
    rm /tmp/setup_pcap.py

    chmod -R 777 /home/user
