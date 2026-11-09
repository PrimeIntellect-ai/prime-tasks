#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate the initial binary configuration files
    cat << 'EOF' > /tmp/setup.py
import struct
import os

def write_config(filepath, data):
    with open(filepath, 'wb') as f:
        # Magic Header + Version
        f.write(b'CONF\x01')
        # Record Count
        f.write(struct.pack('<H', len(data)))

        for k, v in data.items():
            key_bytes = k.encode('ascii')
            f.write(struct.pack('B', len(key_bytes)))
            f.write(key_bytes)

            if isinstance(v, int):
                f.write(b'\x01')
                f.write(struct.pack('<i', v))
            elif isinstance(v, str):
                f.write(b'\x02')
                val_bytes = v.encode('ascii')
                f.write(struct.pack('<H', len(val_bytes)))
                f.write(val_bytes)

data_v1 = {
    "listen_port": 8080,
    "host_address": "127.0.0.1",
    "max_connections": 100,
    "timeout_ms": 5000,
    "ssl_enabled": 1
}

data_v2 = {
    "listen_port": 8081,             # modified
    "host_address": "127.0.0.1",     # unchanged
    "max_connections": 150,          # modified
    # timeout_ms removed
    "ssl_enabled": 1,                # unchanged
    "log_level": "DEBUG"             # added
}

write_config('/home/user/config_v1.bin', data_v1)
write_config('/home/user/config_v2.bin', data_v2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Ensure correct permissions
    chmod -R 777 /home/user
