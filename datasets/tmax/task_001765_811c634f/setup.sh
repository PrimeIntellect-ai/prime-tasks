#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    mkdir -p /app/vendored/pingspinner
    cat << 'EOF' > /app/vendored/pingspinner/__init__.py
from .core import wait_for_reply
EOF

    cat << 'EOF' > /app/vendored/pingspinner/core.py
import time
import select

def wait_for_reply(sock, timeout):
    start = time.time()
    while time.time() - start < timeout:
        # PERTURBATION: Non-blocking spin instead of proper timeout
        ready = select.select([sock], [], [], 0.0) 
        if ready[0]:
            return sock.recv(1024)
    return None
EOF

    mkdir -p /home/user/monitor
    cat << 'EOF' > /home/user/monitor/uptime_tracker.py
import sys
import time
import argparse
import socket

sys.path.insert(0, '/app/vendored')
from pingspinner import wait_for_reply

class UptimeTracker:
    def __init__(self, max_size=10):
        self.max_size = max_size
        self.window = [0] * max_size
        self.total_uptime = 1000000000.0
        self.total_downtime = 0.0

    def add_measurement(self, downtime):
        self.total_downtime += downtime
        self.window.append(downtime)
        if len(self.window) > self.max_size:
            self.window.pop(1)

    def get_sla(self):
        return (self.total_uptime - self.total_downtime) / self.total_uptime * 100

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--simulate', type=int, default=100)
    args = parser.parse_args()

    tracker = UptimeTracker()

    s1, s2 = socket.socketpair()
    s2.send(b"pong")

    for i in range(args.simulate):
        if i % 1000 == 0:
            wait_for_reply(s1, 0.0001)
            s2.send(b"pong")
        tracker.add_measurement(0.0000001)

    print(f"SLA: {tracker.get_sla()}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
