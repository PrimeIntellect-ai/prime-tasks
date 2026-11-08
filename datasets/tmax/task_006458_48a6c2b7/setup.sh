#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the test file with the intentional UTF-8 decoding bug
    cat << 'EOF' > /home/user/test_uptime.py
import json
import binascii

def decode_payload(hex_data: str) -> dict:
    # BUG: Decodes as utf-8 instead of utf-16le
    raw_bytes = binascii.unhexlify(hex_data)
    return json.loads(raw_bytes.decode('utf-8'))

def test_decode():
    # Hex representation of {"service": "auth-db"} in UTF-16LE
    test_hex = "7b002200730065007200760069006300650022003a002000220061007500740068002d006400620022007d00"
    result = decode_payload(test_hex)
    assert result.get("service") == "auth-db"
EOF

    # Generate the memory dump
    python3 -c '
import os
import binascii

# The target JSON payload
payload_str = "{\"service\": \"payment-api\", \"status\": \"down\", \"last_ping\": 1700000000, \"error\": \"OOM\"}"

# Encode to UTF-16LE then to HEX
hex_payload = binascii.hexlify(payload_str.encode("utf-16le")).decode("ascii")

# Create a dummy binary dump
with open("/home/user/monitor_crash.dmp", "wb") as f:
    f.write(os.urandom(1024))
    f.write(b"[UPTIME_CRASH_DUMP_START]")
    f.write(hex_payload.encode("ascii"))
    f.write(b"[UPTIME_CRASH_DUMP_END]")
    f.write(os.urandom(512))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
