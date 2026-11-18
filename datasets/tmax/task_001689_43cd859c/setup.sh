#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential g++ make wget
    pip3 install pytest xxhash

    mkdir -p /app/vendored
    cd /app/vendored
    wget https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.2.tar.gz
    tar -xzf v0.8.2.tar.gz
    rm v0.8.2.tar.gz

    # Apply the deliberate perturbation
    sed -i 's/AR ?= ar/AR = \/bin\/false/g' xxHash-0.8.2/Makefile
    if ! grep -q "AR = /bin/false" xxHash-0.8.2/Makefile; then
        sed -i '1i AR = /bin/false' xxHash-0.8.2/Makefile
    fi

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_hasher.py
#!/usr/bin/env python3
import sys
import xxhash

def process_stream():
    for line in sys.stdin:
        stripped = line.strip()
        if not stripped:
            continue

        # Use seed=42 as the constraint
        h = xxhash.xxh32(stripped, seed=42).intdigest()

        # Logic constraint: only process if hash is even
        if h % 2 == 0:
            # Output 8-character zero-padded hex, followed by reversed string
            print(f"{h:08x} {stripped[::-1]}")

if __name__ == "__main__":
    process_stream()
EOF

    chmod +x /home/user/legacy_hasher.py
    chmod -R 777 /home/user
