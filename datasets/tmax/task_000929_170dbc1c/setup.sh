#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy dpkt

    mkdir -p /home/user/forensics
    cd /home/user/forensics

    cat << 'EOF' > generate_artifacts.py
import time
from scapy.all import *
import random

pcap_file = '/home/user/forensics/traffic.pcap'
log_file = '/home/user/forensics/server.log'

malicious_ip = '192.168.1.105'
target_ip = '10.0.0.5'
payload_uri = '/?action=pay&token=1%27%3BDROP+TABLE+transactions%3B--'

packets = []
log_entries = bytearray()

# Normal traffic
for i in range(5):
    ip = f"192.168.1.{10+i}"
    pkt = IP(src=ip, dst=target_ip)/TCP(sport=random.randint(1024, 65535), dport=80)/f"GET / HTTP/1.1\r\nHost: {target_ip}\r\n\r\n"
    pkt.time = 1698417000 + i
    packets.append(pkt)

    log_line = f"[{time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(pkt.time))}] [{ip}] [INFO] Request processed\n".encode('utf-8')
    log_entries.extend(log_line)

# Malicious packet
malicious_time = 1698417010
mal_pkt = IP(src=malicious_ip, dst=target_ip)/TCP(sport=44444, dport=80)/f"GET {payload_uri} HTTP/1.1\r\nHost: {target_ip}\r\n\r\n"
mal_pkt.time = malicious_time
packets.append(mal_pkt)

# Corrupted log entry for malicious packet
# Injecting null bytes and invalid UTF-8 \xff
mal_time_str = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(malicious_time))
corrupted_line = b"[" + mal_time_str[:10].encode('utf-8') + b"\x00" + mal_time_str[10:].encode('utf-8') + b"] [\xff\xfe" + malicious_ip.encode('utf-8') + b"\x00] [CRITICAL] Payment Gateway Crash: invalid input\n"
log_entries.extend(corrupted_line)

# More normal traffic
for i in range(5):
    ip = f"192.168.1.{20+i}"
    pkt = IP(src=ip, dst=target_ip)/TCP(sport=random.randint(1024, 65535), dport=80)/f"GET /status HTTP/1.1\r\nHost: {target_ip}\r\n\r\n"
    pkt.time = 1698417015 + i
    packets.append(pkt)

    log_line = f"[{time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(pkt.time))}] [{ip}] [INFO] Health check\n".encode('utf-8')
    log_entries.extend(log_line)

wrpcap(pcap_file, packets)

with open(log_file, 'wb') as f:
    f.write(log_entries)

EOF

    python3 generate_artifacts.py
    rm generate_artifacts.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
