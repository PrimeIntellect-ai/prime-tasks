#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import gzip
import random

os.makedirs('/home/user/raw_artifacts', exist_ok=True)
os.makedirs('/home/user/metadata', exist_ok=True)

# Generate raw artifacts
random.seed(42)
for i in range(1, 21):
    filename = f"/home/user/raw_artifacts/artifact_{i:02d}.bin.gz"
    arch = "ARCH_X86" if random.random() > 0.5 else "ARCH_ARM"

    # Create dummy binary data: 8 bytes header + 1024 bytes random
    dummy_data = arch.encode('ascii') + os.urandom(1024)

    with gzip.open(filename, 'wb') as f:
        f.write(dummy_data)

# Generate manifest
with open('/home/user/metadata/manifest.txt', 'w') as f:
    for i in range(50000):
        if i % 10 == 0:
            f.write(f"Line {i}: Uploading to SERVER_A_DEPRECATED/path/{i}\n")
        else:
            f.write(f"Line {i}: Normal build log entry.\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
