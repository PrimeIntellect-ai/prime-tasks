#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_build/configs
    cd /home/user/system_build

    cat << 'EOF' > configs/service_A.json
{
  "name": "service_A",
  "allowed_ports": [8000, 8001, 8002],
  "retries": 3
}
EOF

    cat << 'EOF' > configs/service_B.json
{
  "name": "service_B",
  "allowed_ports": [8001, 8002],
  "timeout": 30
}
EOF

    cat << 'EOF' > configs/service_C.json
{
  "name": "service_C",
  "allowed_ports": [8002],
  "secure": true
}
EOF

    cat << 'EOF' > configs/service_D.json
{
  "name": "service_D",
  "allowed_ports": [8000, 8001, 8002, 8003],
  "debug": false
}
EOF

    cat << 'EOF' > build_pack.py
import os
import json
import struct
import zlib

def build():
    config_dir = "configs"
    services = []

    # Read configs
    for f in os.listdir(config_dir):
        if f.endswith('.json'):
            with open(os.path.join(config_dir, f), 'r') as fp:
                data = fp.read()
                js = json.loads(data)
                services.append({"name": js["name"], "data": data, "allowed": js["allowed_ports"]})

    services.sort(key=lambda x: x["name"])

    # Buggy greedy assignment
    assigned_ports = set()
    for s in services:
        for p in s["allowed"]:
            if p not in assigned_ports:
                s["port"] = p
                assigned_ports.add(p)
                break

    # Buggy Serialization
    out = b"PACK"
    out += struct.pack("<H", len(services)) # Bug: little endian

    for s in services:
        out += struct.pack("B", len(s["name"]))
        out += s["name"].encode('ascii')
        out += struct.pack("<H", s["port"]) # Bug: little endian
        out += struct.pack("<I", len(s["data"])) # Bug: little endian
        out += s["data"].encode('utf-8')

    # Buggy checksum
    crc = zlib.crc32(out) & 0xFFFFFFFF
    out += struct.pack("<I", crc) # Bug: little endian

    with open("output.pack", "wb") as f:
        f.write(out)

if __name__ == "__main__":
    build()
EOF

    chmod -R 777 /home/user
