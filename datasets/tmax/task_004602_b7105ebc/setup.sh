#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.log
2023-10-15 08:23:45 [192.168.1.50] User login successful
2023-10-15 08:24:10 [10.0.0.5] Database connection established
2023-10-15 08:25:00 [172.16.254.1] Timeout error
EOF

    python3 -c '
import struct
lines = [
    (1697358225, 0),
    (1697358250, 53),
    (1697358300, 116)
]
with open("/home/user/.expected_index.bin", "wb") as f:
    for ts, offset in lines:
        f.write(struct.pack("<QQ", ts, offset))
'

    chmod -R 777 /home/user
