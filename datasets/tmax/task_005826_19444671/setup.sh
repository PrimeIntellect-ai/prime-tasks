#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    mkdir -p /home/user/app
    mkdir -p /home/user/data
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/app/server.js
const net = require('net');

// Dummy API gateway
// Real system would receive HTTP requests and forward to worker.
EOF

    cat << 'EOF' > /home/user/app/worker.py
import socket
import struct
import json
import sys

def handle_client(conn):
    try:
        header = conn.recv(5)
        if not header or len(header) < 5:
            return
        msg_type = header[0]
        length = struct.unpack('>I', header[1:5])[0]

        # Bug: Doesn't check if length is valid, just reads up to length
        data = conn.recv(length)

        if msg_type == 2:
            # Bug: if data is truncated in the middle of a utf-8 char, it crashes
            # and if it's invalid JSON, it crashes
            text = data.decode('utf-8')
            payload = json.loads(text)
            response = json.dumps({"status": "ok"}).encode('utf-8')
            conn.sendall(struct.pack('>BI', 2, len(response)) + response)
    except ConnectionResetError:
        pass

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 9000))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        handle_client(conn)
        conn.close()

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/logs/server.log
[INFO] Server started
[INFO] Received request from 192.168.100.42
[ERROR] Worker connection closed unexpectedly
EOF

    cat << 'EOF' > /home/user/logs/worker.log
[INFO] Worker started
[INFO] Processing message type 2
Traceback (most recent call last):
  File "worker.py", line 20, in handle_client
    text = data.decode('utf-8')
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xc3 in position 8: unexpected end of data
EOF

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *

pkts = []
# HTTP request
ip1 = IP(src="192.168.100.42", dst="10.0.0.1")
tcp1 = TCP(sport=12345, dport=80, flags="PA")
payload1 = "POST /api/data HTTP/1.1\r\nHost: 10.0.0.1\r\n\r\n"
pkts.append(ip1/tcp1/payload1)

# TCP packet to worker
ip2 = IP(src="127.0.0.1", dst="127.0.0.1")
tcp2 = TCP(sport=8000, dport=9000, flags="PA")
payload2 = b'\x02\x00\x00\x00\x64' + b'{"test":"\xc3'
pkts.append(ip2/tcp2/payload2)

wrpcap("/home/user/data/traffic.pcap", pkts)
EOF

    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
