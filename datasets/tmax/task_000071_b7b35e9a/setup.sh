#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import struct

os.makedirs('/home/user/artifacts/project_alpha/v1', exist_ok=True)
os.makedirs('/home/user/artifacts/project_beta', exist_ok=True)
os.makedirs('/home/user/artifacts/project_gamma', exist_ok=True)

MAGIC = 0xDEADC0DE

# Valid file 1
with open('/home/user/artifacts/project_alpha/v1/data1.bin', 'wb') as f:
    f.write(struct.pack('<I', MAGIC))
    f.write(struct.pack('<d', 1.2345678))
    f.write(struct.pack('<d', -9.8765432))
    f.write(struct.pack('<d', 0.0))

# Valid file 2
with open('/home/user/artifacts/project_beta/metrics.bin', 'wb') as f:
    f.write(struct.pack('<I', MAGIC))
    f.write(struct.pack('<d', 3.14159265))

# Tmp file (should be ignored, not logged as corrupt either)
with open('/home/user/artifacts/project_beta/metrics.bin.tmp', 'wb') as f:
    f.write(struct.pack('<I', MAGIC))
    f.write(struct.pack('<d', 2.71828))

# Corrupt file 1: Bad magic number
with open('/home/user/artifacts/project_gamma/bad_magic.bin', 'wb') as f:
    f.write(struct.pack('<I', 0xBAADF00D))
    f.write(struct.pack('<d', 1.1111))

# Corrupt file 2: Truncated float
with open('/home/user/artifacts/project_gamma/truncated.bin', 'wb') as f:
    f.write(struct.pack('<I', MAGIC))
    f.write(b'\x01\x02\x03\x04') # Only 4 bytes of a float
"

    chmod -R 777 /home/user
