#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import py_compile
import base64
import struct
from scapy.all import wrpcap, IP, TCP, Ether

# Create and compile telemetry_lib.py
with open('/home/user/telemetry_lib.py', 'w') as f:
    f.write('''import base64
import struct

def encode_payload(data: bytes) -> bytes:
    xored = bytes(b ^ 0x5A for b in data)
    b64 = base64.b64encode(xored)
    return struct.pack('>I', len(b64)) + b64
''')

py_compile.compile('/home/user/telemetry_lib.py', cfile='/home/user/telemetry_lib.pyc')

# Generate capture.pcap
def encode_payload(data: bytes) -> bytes:
    xored = bytes(b ^ 0x5A for b in data)
    b64 = base64.b64encode(xored)
    return struct.pack('>I', len(b64)) + b64

packets = []
payload1 = encode_payload(b"SENSOR_DATA_99.8_OK")
payload2 = encode_payload(b"SYSTEM_INIT_CRASH_OVERRIDE_V1_TRIGGER")

pkt1 = Ether()/IP(dst="127.0.0.1", src="127.0.0.1")/TCP(dport=8001, sport=12345)/payload1
pkt2 = Ether()/IP(dst="127.0.0.1", src="127.0.0.1")/TCP(dport=8001, sport=12345)/payload2

wrpcap('/home/user/capture.pcap', [pkt1, pkt2])
EOF

    python3 /tmp/setup.py
    rm /home/user/telemetry_lib.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
