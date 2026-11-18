#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark sleuthkit e2fsprogs e2tools
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    # Create packet capture
    cat << 'EOF' > /tmp/make_pcap.py
from scapy.all import *
packets = []
packets.append(IP(src="192.168.1.10", dst="10.0.0.5")/TCP(sport=12345, dport=80)/Raw(load="GET /api/v1/health HTTP/1.1\r\nHost: gateway\r\n\r\n"))
packets.append(IP(src="192.168.1.15", dst="10.0.0.5")/TCP(sport=12346, dport=80)/Raw(load="GET /api/v1/status HTTP/1.1\r\nHost: gateway\r\n\r\n"))
packets.append(IP(src="172.16.42.99", dst="10.0.0.5")/TCP(sport=54321, dport=80)/Raw(load="GET /api/v1/explode HTTP/1.1\r\nHost: gateway\r\n\r\n"))
wrpcap('/home/user/capture.pcap', packets)
EOF
    python3 /tmp/make_pcap.py

    # Create log file
    cat << 'EOF' > /tmp/gateway.log
[2023-11-01 02:50:00] INFO: Request from 192.168.1.10 to /api/v1/health - 200 OK
[2023-11-01 02:51:12] INFO: Request from 192.168.1.15 to /api/v1/status - 200 OK
[2023-11-01 02:59:59] ERROR: Exception on /api/v1/explode [GET]
Traceback (most recent call last):
  File "app.py", line 102, in handle_request
    process_payment()
  File "payments.py", line 45, in process_payment
    raise RecursionError("Maximum recursion depth exceeded during payment processing")
RecursionError: Maximum recursion depth exceeded during payment processing
Request from 172.16.42.99 caused fatal crash.
EOF

    # Create ext4 image, copy log, and delete it using e2tools (avoids needing mount privileges)
    dd if=/dev/zero of=/home/user/storage.img bs=1M count=10
    mkfs.ext4 -F /home/user/storage.img
    e2cp /tmp/gateway.log /home/user/storage.img:/gateway.log
    e2rm /home/user/storage.img:/gateway.log

    chmod -R 777 /home/user
