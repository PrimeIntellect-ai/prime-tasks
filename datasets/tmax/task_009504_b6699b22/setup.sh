#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/daemon_proc.py
import os
import time
import json

config_path = "/home/user/config.json"
with open(config_path, "w") as f:
    json.dump({"max_retries": 5, "timeout": 30}, f)

# Hold the file open
f = open(config_path, "r")

# Delete the file from the filesystem
os.unlink(config_path)

# Hang forever to simulate the deadlock
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/make_pcap.py
import struct

payload = '{"event":"critical_failure"}'.encode('utf-16le')

# Pcap global header
pcap = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

packet_len = 42 + len(payload)
pcap += struct.pack('<IIII', 0, 0, packet_len, packet_len)

# Ethernet (14 bytes)
pcap += b'\x00' * 14

# IP (20 bytes)
ip_header = b'\x45\x00' + struct.pack('>H', 28 + len(payload)) + b'\x00\x00\x00\x00\x40\x11\x00\x00' + b'\x7f\x00\x00\x01' + b'\x7f\x00\x00\x01'
pcap += ip_header

# UDP (8 bytes)
udp_header = struct.pack('>HHHH', 9999, 9999, 8 + len(payload), 0)
pcap += udp_header

# Payload
pcap += payload

with open('/home/user/traffic.pcap', 'wb') as f:
    f.write(pcap)
EOF

    python3 /home/user/make_pcap.py
    rm /home/user/make_pcap.py

    # Start the daemon whenever the container environment is loaded
    cat << 'EOF' > /.singularity.d/env/99-daemon.sh
#!/bin/bash
if ! pgrep -f "python3 /home/user/daemon_proc.py" > /dev/null; then
    python3 /home/user/daemon_proc.py &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-daemon.sh

    chmod -R 777 /home/user
