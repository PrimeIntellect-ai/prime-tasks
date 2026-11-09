#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev jq libssl-dev sudo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/create_snapshot.py
import struct
import gzip

config_data = """[General]
AppName=LegacyConf
Version=1.0.4
Author=Admin

[Network]
IPAddress=10.0.5.55
Port=9090
Gateway=10.0.5.1
Protocol=TCP

[Database]
Host=localhost
User=root

[Security]
EnableSSL=true
CertPath=/etc/ssl/certs/legacy.crt
MaxConnections=50
"""

compressed_payload = gzip.compress(config_data.encode('utf-8'))

magic = b'CFGS'
timestamp = 1715000000
comp_size = len(compressed_payload)
uncomp_size = len(config_data.encode('utf-8'))

header = struct.pack('<4sIII', magic, timestamp, comp_size, uncomp_size)

with open('/home/user/config_snapshot.dat', 'wb') as f:
    f.write(header + compressed_payload)
EOF

    python3 /home/user/create_snapshot.py
    rm /home/user/create_snapshot.py

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
