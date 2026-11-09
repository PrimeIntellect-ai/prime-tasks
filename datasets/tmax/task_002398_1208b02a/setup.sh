#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/staging
    mkdir -p /home/user/incoming

    python3 -c '
import struct

def write_record(f, timestamp, payload):
    payload_bytes = payload.encode("ascii")
    f.write(b"DATA")
    f.write(struct.pack("<I", timestamp))
    f.write(struct.pack("<H", len(payload_bytes)))
    f.write(payload_bytes)

with open("/home/user/staging/fileA.bin", "wb") as f:
    write_record(f, 1630000000, "System initialized.")
    write_record(f, 1630000005, "Module A loaded.")

with open("/home/user/staging/fileB.bin", "wb") as f:
    write_record(f, 1630000010, "Warning: low memory.")

with open("/home/user/staging/fileC.bin", "wb") as f:
    write_record(f, 1630000020, "User logged in.")
    write_record(f, 1630000025, "Data sync complete.")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
