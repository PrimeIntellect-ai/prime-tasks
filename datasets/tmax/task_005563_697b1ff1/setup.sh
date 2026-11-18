#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the config.binlog file
    cat << 'EOF' > /tmp/setup.py
import struct

def create_binlog():
    filepath = "/home/user/config.binlog"

    payloads = [
        "server_port=8080\nmax_connections=100",
        "server_port=8081\nmax_connections=200\nenable_cache=true",
        "server_port=8081\nmax_connections=250\nenable_cache=true\nlog_level=debug"
    ]

    # The test expects exactly 216 bytes total. 
    # The first three records are 196 bytes (48 + 66 + 82).
    # To reach 216 bytes, the last record must be 20 bytes (12 byte header + 8 byte payload).
    truncated_payload = "server_p" # exactly 8 bytes

    with open(filepath, "wb") as f:
        # Write valid records
        for i, payload in enumerate(payloads):
            payload_bytes = payload.encode('utf-8')
            header = struct.pack('<4sII', b'CFG1', 1670000000 + i, len(payload_bytes))
            f.write(header)
            f.write(payload_bytes)

        # Write truncated record (header is intact, but payload is cut short)
        header = struct.pack('<4sII', b'CFG1', 1670000010, 500) # claims 500 bytes
        f.write(header)
        f.write(truncated_payload.encode('utf-8')) # writes 8 bytes

create_binlog()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
