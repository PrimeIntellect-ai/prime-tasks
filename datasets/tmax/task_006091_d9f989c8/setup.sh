#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import os
import json
import base64
import struct
import time

# Create billing.py
billing_code = """import json
import sys

def process(file_path):
    with open(file_path) as f:
        # BUG: json.load parses floats as standard IEEE 754 floats
        data = json.load(f)

    total = 0.0
    for tx in data['transactions']:
        total += tx['amount']

    expected = float(data['expected_total'])

    # We round to avoid standard minor float errors, but the extreme precision loss will still trigger this
    if round(total, 2) != round(expected, 2):
        raise ValueError(f"ChecksumMismatchError: calculated {total} != expected {expected}")

    print(f"Success. Total: {total}")
    with open('/home/user/total.txt', 'w') as out_f:
        out_f.write(str(data['expected_total']))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python billing.py <input.json>")
        sys.exit(1)
    process(sys.argv[1])
"""

with open('/home/user/billing.py', 'w') as f:
    f.write(billing_code)

# Create JSON payload
payload = {
    "expected_total": "10000000000000000.05",
    "transactions": [
        {"id": "tx_normal_1", "amount": 100.0},
        {"id": "tx_giant_bug", "amount": 10000000000000000.0},
        {"id": "tx_micro_1", "amount": 0.02},
        {"id": "tx_micro_2", "amount": 0.03},
        {"id": "tx_normal_2", "amount": -100.0}
    ]
}
json_payload = json.dumps(payload)

# Create a fake pcap with the json payload in plaintext (simulating unencrypted HTTP)
pcap_global_header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)
packet_data = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" + json_payload.encode()
ts_sec = int(time.time())
ts_usec = 0
incl_len = len(packet_data)
orig_len = len(packet_data)
pcap_packet_header = struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len)

with open('/home/user/billing_dump.pcap', 'wb') as f:
    f.write(pcap_global_header)
    f.write(pcap_packet_header)
    f.write(packet_data)

os.system('chmod +x /home/user/billing.py')
EOF

    python3 /tmp/setup_task.py
    chmod -R 777 /home/user
