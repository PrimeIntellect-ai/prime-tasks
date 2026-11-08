#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nodejs tcpdump
pip3 install pytest scapy

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/server.py
import socket
import json
import sys

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9000))
    server.listen(5)

    while True:
        try:
            conn, addr = server.accept()
            data = conn.recv(1024)
            if not data:
                conn.close()
                continue

            msg = json.loads(data.decode('utf-8'))

            if msg.get('action') == 'ping':
                conn.sendall(b'{"status": "pong"}')
            elif msg.get('action') == 'update_profile':
                # BUG: KeyError if 'user_id' is missing. Unhandled exception crashes the while loop.
                user_id = msg['user_id']
                conn.sendall(b'{"status": "updated"}')
            else:
                conn.sendall(b'{"status": "unknown"}')

            conn.close()
        except json.JSONDecodeError:
            pass # Ignore bad JSON
        # Missing general Exception block or specific KeyError block causes crash
EOF

cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import *

packets = []
# Handshake 1
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50000, dport=9000, flags="S", seq=1000))
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=9000, dport=50000, flags="SA", seq=2000, ack=1001))
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50000, dport=9000, flags="A", seq=1001, ack=2001))
# Valid request
payload1 = b'{"action": "ping"}'
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50000, dport=9000, flags="PA", seq=1001, ack=2001)/Raw(load=payload1))
# Handshake 2 (Poison pill)
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50001, dport=9000, flags="S", seq=3000))
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=9000, dport=50001, flags="SA", seq=4000, ack=3001))
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50001, dport=9000, flags="A", seq=3001, ack=4001))
# Poison request (missing user_id)
payload2 = b'{"action": "update_profile", "data": "new_avatar.png"}'
packets.append(IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50001, dport=9000, flags="PA", seq=3001, ack=4001)/Raw(load=payload2))

wrpcap('/home/user/incident.pcap', packets)
EOF

python3 /home/user/generate_pcap.py
rm /home/user/generate_pcap.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
