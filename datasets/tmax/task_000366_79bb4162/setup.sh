#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow scapy

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os, json
from PIL import Image, ImageDraw
from scapy.all import IP, TCP, Raw, wrpcap

# Generate Image
img = Image.new('RGB', (1000, 300), color='white')
d = ImageDraw.Draw(img)
text = """MATHEMATICAL SPECIFICATION:
Formula: result = (var_alpha * var_beta) / (var_alpha - var_beta)
Constraint 1: var_alpha MUST NOT equal var_beta.
Constraint 2: Both var_alpha and var_beta must be strictly numeric values (integers or floats). Reject strings, even if they look like numbers.
Constraint 3: Reject if any other keys are present in the JSON."""
d.text((10,10), text, fill='black')
img.save('/app/spec.png')

# Generate PCAP
pkts = []
for i in range(5):
    payload = '{"var_alpha": 10, "var_beta": 5}'
    req = f"POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: {len(payload)}\r\n\r\n{payload}"
    pkt = IP(dst="127.0.0.1")/TCP(dport=80)/Raw(load=req)
    pkts.append(pkt)
wrpcap('/app/traffic.pcap', pkts)

# Generate Clean Corpus
for i in range(25):
    with open(f'/app/corpus/clean/clean_{i}.json', 'w') as f:
        json.dump({"var_alpha": i+10, "var_beta": i}, f)

# Generate Evil Corpus
evil_cases = [
    {"var_alpha": 5, "var_beta": 5},
    {"var_alpha": "10", "var_beta": 5},
    {"var_alpha": 10, "var_beta": 5, "extra": 1},
    {"var_alpha": None, "var_beta": 5},
    {"var_beta": 5}
]
for i in range(25):
    case = evil_cases[i % len(evil_cases)]
    with open(f'/app/corpus/evil/evil_{i}.json', 'w') as f:
        json.dump(case, f)
EOF

    python3 /tmp/setup.py

    cat << 'EOF' > /app/legacy_validator.py
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
a = float(data['var_alpha'])
b = float(data['var_beta'])
res = (a * b) / (a - b)
print(res)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
