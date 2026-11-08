#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    # Generate traffic.pcap and replay.py
    cat << 'EOF' > /tmp/setup.py
import os
import json
import struct
from scapy.all import IP, UDP, Ether, wrpcap

pcap_file = '/home/user/traffic.pcap'
packets = []

# Generate 100 metrics packets
for i in range(100):
    # Payload: metric_id (1-5), value (10)
    metric_id = (i % 5) + 1
    payload = json.dumps({"id": f"metric_{metric_id}", "val": 10}).encode('utf-8')
    pkt = Ether()/IP(dst="127.0.0.1")/UDP(sport=12345, dport=9042)/payload
    packets.append(pkt)

# Generate SHUTDOWN packet
shutdown_payload = b"SHUTDOWN"
pkt = Ether()/IP(dst="127.0.0.1")/UDP(sport=12345, dport=9042)/shutdown_payload
packets.append(pkt)

wrpcap(pcap_file, packets)

replay_script = """import sys
from scapy.all import rdpcap, UDP, IP
import socket

if len(sys.argv) != 2:
    print("Usage: python3 replay.py <port>")
    sys.exit(1)

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
packets = rdpcap('/home/user/traffic.pcap')

for pkt in packets:
    if UDP in pkt:
        sock.sendto(bytes(pkt[UDP].payload), ('127.0.0.1', port))
"""
with open('/home/user/replay.py', 'w') as f:
    f.write(replay_script)
EOF

    python3 /tmp/setup.py

    # Create server.py
    cat << 'EOF' > /home/user/server.py
import socketserver
import json
import sys
import os
import time
import threading

# Global state
state = {}
# No lock! This is the bug.

class MetricsHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data = self.request[0].strip()
        sock = self.request[1]

        if data == b"SHUTDOWN":
            with open('/home/user/metrics_out.json', 'w') as f:
                json.dump(state, f)
            # Kill server
            threading.Thread(target=self.server.shutdown).start()
            return

        try:
            msg = json.loads(data.decode('utf-8'))
            m_id = msg['id']
            m_val = msg['val']

            # RACE CONDITION HERE
            current = state.get(m_id, 0)
            time.sleep(0.01) # Force thread yield to guarantee race condition
            state[m_id] = current + m_val

        except Exception as e:
            print(f"Error processing {data}: {e}")

if __name__ == "__main__":
    # Deliberately silent exit if config is missing to force strace
    if not os.path.exists('/home/user/server_conf.json'):
        sys.exit(0)

    with open('/home/user/server_conf.json', 'r') as f:
        conf = json.load(f)

    port = conf.get('port', 0)
    server = socketserver.ThreadingUDPServer(('127.0.0.1', port), MetricsHandler)
    server.serve_forever()
EOF

    chmod -R 777 /home/user
