#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/config.py
import os

class Config:
    DEBUG = os.getenv('DEBUG', '0')
    MAX_RETRIES = int(os.getenv('MAX_RETRIES', '3'))
    # If set to '1', corrupted payloads are flushed instead of cached for retry
    FLUSH_ON_ERROR = os.getenv('FLUSH_ON_ERROR', '0')
EOF

cat << 'EOF' > /home/user/.env
DEBUG=1
MAX_RETRIES=5
EOF

# Generate the memory dump using Python to avoid shell specific escape issues
python3 -c '
import os
with open("/home/user/service_mem.dump", "wb") as f:
    f.write(os.urandom(100000))
    for _ in range(5000):
        f.write(b"PAYLOAD_ID_9921_CORRUPT_MAGIC_0xBAADF00D\x00\x01\x02")
    for _ in range(10):
        f.write(b"PAYLOAD_ID_1111_VALID_0x00000000\x00\x00\x00")
    f.write(os.urandom(50000))
'

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
