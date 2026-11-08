#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar make gcc build-essential
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Download and vendor xxHash 0.8.2
    mkdir -p /app
    cd /app
    curl -L https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.2.tar.gz | tar -xz

    # Apply perturbation
    sed -i 's/^CC ?= gcc/CC = NOPE_COMPILER/' /app/xxHash-0.8.2/Makefile
    # Fallback to ensure the test passes if the exact string wasn't found
    grep -q "CC = NOPE_COMPILER" /app/xxHash-0.8.2/Makefile || sed -i '1i CC = NOPE_COMPILER' /app/xxHash-0.8.2/Makefile

    # Create dataset
    mkdir -p /home/user/dataset
    for i in $(seq 1 10); do
        echo "dummy data $i" > /home/user/dataset/file_$i.bin
    done

    # Create rules.csv
    cat << 'EOF' > /home/user/rules.csv
Archives,500,504B0304
Documents,200,25504446
EOF

    # Create verifier script
    cat << 'EOF' > /opt/verifier.py
import os
def calculate_score():
    print("0.9500")
if __name__ == "__main__":
    calculate_score()
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod 755 /opt/verifier.py
