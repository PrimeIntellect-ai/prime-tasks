#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tshark
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_system

    # 1. Create and compile auth_checker
    cat << 'EOF' > /home/user/ticket_system/auth_checker.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    // Obfuscated string to prevent simple 'strings' without minor analysis
    // "OVR-9982-ADMIN-SYS"
    char master[] = { 'O', 'V', 'R', '-', '9', '9', '8', '2', '-', 'A', 'D', 'M', 'I', 'N', '-', 'S', 'Y', 'S', '\0' };

    if (strcmp(argv[1], master) == 0) {
        return 0; // Success
    }
    // Simulate normal auth logic (dummy)
    if (strlen(argv[1]) == 10) {
        return 0;
    }
    return 2; // Fail
}
EOF
    gcc /home/user/ticket_system/auth_checker.c -o /home/user/ticket_system/auth_checker
    chmod +x /home/user/ticket_system/auth_checker
    rm /home/user/ticket_system/auth_checker.c

    # 2. Create ticket_router.py
    cat << 'EOF' > /home/user/ticket_system/ticket_router.py
import socket
import threading
import json
import subprocess
import time

processed_count = 0

def handle_client(conn):
    global processed_count
    try:
        data = conn.recv(1024)
        if not data: return
        req = json.loads(data.decode())

        res = subprocess.run(['./auth_checker', req.get('token', '')], capture_output=True)
        if res.returncode != 0:
            conn.send(b"AUTH_FAIL")
            return

        # Race condition: non-atomic read/modify/write with sleep to force the race
        current = processed_count
        time.sleep(0.05) 
        processed_count = current + 1

        # Another race: unprotected file write (can interleave)
        with open("processed_tickets.log", "a") as f:
            f.write(f"{req['id']}\n")

        conn.send(b"OK")
    except Exception as e:
        pass
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(100)

    while True:
        conn, addr = s.accept()
        t = threading.Thread(target=handle_client, args=(conn,))
        t.start()

if __name__ == '__main__':
    main()
EOF

    # 3. Generate PCAP
    cat << 'EOF' > /home/user/ticket_system/generate_pcap.py
from scapy.all import *
import json

packets = []
# Create 5 TCP sessions. Ticket 3 will be the "missing" one.
tickets = ["TKT-1001", "TKT-1002", "TKT-1003", "TKT-1004", "TKT-1005"]

for i, t_id in enumerate(tickets):
    payload = json.dumps({"id": t_id, "token": "abcdefghij"})
    # Mocking TCP handshake and data push (just enough for scapy/tshark to read payloads)
    p = IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=50000+i, dport=8888, flags="PA")/Raw(load=payload)
    packets.append(p)

wrpcap("/home/user/ticket_system/capture.pcap", packets)
EOF
    python3 /home/user/ticket_system/generate_pcap.py
    rm /home/user/ticket_system/generate_pcap.py

    # 4. Create initial log
    cat << 'EOF' > /home/user/ticket_system/processed_tickets.log
TKT-1001
TKT-1002
TKT-1004
TKT-1005
EOF

    chmod -R 777 /home/user
