#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/legacy_repo/logs
mkdir -p /home/user/legacy_repo/pcap
mkdir -p /home/user/legacy_repo/src

cd /home/user/legacy_repo
git init
git config user.name "Old Dev"
git config user.email "old@dev.com"

# Commit 1: Initial code
cat << 'EOF' > src/pipeline.py
import requests
import json

def run_pipeline(api_key, endpoint):
    payload = {"data": "test"}
    headers = {"X-API-Key": api_key}
    response = requests.post(f"https://api.internal.corp{endpoint}", json=payload, headers=headers)
    response.raise_for_status()
EOF
git add src/pipeline.py
git commit -m "Initial commit of pipeline script"

# Commit 2: Accidentally commit secret
cat << 'EOF' > config.json
{
  "api_key": "SECRET-99xJ2-44mAq-11bZw",
  "endpoint": "/v3/telemetry/ingest"
}
EOF
git add config.json
git commit -m "Add local dev config"

# Commit 3: Remove secret
rm config.json
cat << 'EOF' > config.json.template
{
  "api_key": "YOUR_KEY_HERE",
  "endpoint": "YOUR_ENDPOINT_HERE"
}
EOF
git add config.json.template
git rm config.json
git commit -m "Remove sensitive config, add template"

# Create the crash log
cat << 'EOF' > /home/user/legacy_repo/logs/crash.log
Traceback (most recent call last):
  File "src/main.py", line 42, in <module>
    main()
  File "src/main.py", line 38, in main
    run_pipeline(config['api_key'], config['endpoint'])
  File "/home/user/legacy_repo/src/pipeline.py", line 7, in run_pipeline
    response = requests.post(f"https://api.internal.corp{endpoint}", json=payload, headers=headers)
ValueError: api_key cannot be 'YOUR_KEY_HERE' and endpoint cannot be 'YOUR_ENDPOINT_HERE'. Authentication and routing failed.
EOF

# Create the PCAP file using python
cat << 'EOF' > /tmp/write_pcap.py
import struct
import time

def write_http_pcap(filename):
    # Minimal PCAP file generator for an HTTP POST request
    # Ethernet + IPv4 + TCP + HTTP POST

    pcap_global_header = struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

    # Raw HTTP payload
    http_data = b"POST /v3/telemetry/ingest HTTP/1.1\r\nHost: api.internal.corp\r\nX-API-Key: SECRET-99xJ2-44mAq-11bZw\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"data\":\"test\"}"

    # Fake MACs, IPs, Ports
    eth = b'\x00\x11\x22\x33\x44\x55\xaa\xbb\xcc\xdd\xee\xff\x08\x00'
    ipv4 = b'\x45\x00\x00' + struct.pack('>H', 40 + len(http_data)) + b'\x00\x00\x40\x00\x40\x06\x00\x00\xc0\xa8\x01\x05\xc0\xa8\x01\x0a'
    tcp = b'\x1f\x90\x00\x50\x00\x00\x00\x01\x00\x00\x00\x01\x50\x18\xff\xff\x00\x00\x00\x00'

    packet = eth + ipv4 + tcp + http_data

    ts_sec = int(time.time())
    ts_usec = 0
    incl_len = len(packet)
    orig_len = len(packet)

    pcap_packet_header = struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len)

    with open(filename, 'wb') as f:
        f.write(pcap_global_header)
        f.write(pcap_packet_header)
        f.write(packet)

write_http_pcap('/home/user/legacy_repo/pcap/session.pcap')
EOF

python3 /tmp/write_pcap.py
rm /tmp/write_pcap.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
