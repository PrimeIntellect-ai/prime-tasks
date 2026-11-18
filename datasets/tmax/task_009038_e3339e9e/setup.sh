#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd tar gzip
    pip3 install pytest

    mkdir -p /home/user/recovery/data
    mkdir -p /home/user/recovery/logs

    python3 -c '
import os
with open("/home/user/recovery/data/alpha.dat", "wb") as f:
    f.write(b"\x89\x50\x4E\x47" + b"\x00" * (15 * 1024))
with open("/home/user/recovery/data/beta.dat", "wb") as f:
    f.write(b"\x00\x01\x02\x03" + b"\x00" * (4 * 1024))
with open("/home/user/recovery/data/gamma.dat", "wb") as f:
    f.write(b"\xCA\xFE\xBA\xBE" + b"\x00" * (20 * 1024))
'

    cat << 'EOF' > /home/user/recovery/logs/access.log
Connection from 192.168.1.45 on port 22
Failed login from 10.0.0.5
Valid access from 127.0.0.1
EOF

    cat << 'EOF' > /home/user/recovery/logs/system.log
Kernel panic: issue with node 172.16.254.1
Resolved node 8.8.8.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
