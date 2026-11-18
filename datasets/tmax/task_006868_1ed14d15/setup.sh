#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump tshark
    pip3 install pytest scapy

    mkdir -p /home/user/monitor_service

    cat << 'EOF' > /home/user/monitor_service/server.py
import socket, threading, os

lock = threading.Lock()
metrics = {}

def handle_client(data):
    text = data.decode('utf-8')
    parts = text.split('|')
    if len(parts) >= 2:
        try:
            k = parts[0].split('=')[1]
            v = parts[1].split('=')[1]
        except IndexError:
            return

        lock.acquire()
        # Edge case: if value contains 'NaN_ERROR', it raises an exception before releasing lock
        if 'NaN_ERROR' in v:
            raise ValueError("Invalid metric value format")

        metrics[k] = v
        lock.release()

def start_server():
    port = os.environ.get('MONITOR_PORT')
    if not port:
        raise RuntimeError("MONITOR_PORT environment variable not set")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', int(port)))

    while True:
        data, addr = sock.recvfrom(1024)
        t = threading.Thread(target=handle_client, args=(data,))
        t.start()

if __name__ == "__main__":
    start_server()
EOF

    python3 -c "
from scapy.all import IP, UDP, send, wrpcap
packets = [
    IP(dst='127.0.0.1')/UDP(dport=8888)/b'metric=CPU|val=45',
    IP(dst='127.0.0.1')/UDP(dport=8888)/b'metric=MEM|val=1024',
    IP(dst='127.0.0.1')/UDP(dport=8888)/b'metric=DISK|val=NaN_ERROR_99',
    IP(dst='127.0.0.1')/UDP(dport=8888)/b'metric=NET|val=10'
]
wrpcap('/home/user/traffic.pcap', packets)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
