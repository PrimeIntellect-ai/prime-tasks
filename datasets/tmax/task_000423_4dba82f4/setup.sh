#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        autoconf \
        automake \
        wget \
        tar

    pip3 install pytest

    # Create directories
    mkdir -p /app /opt/oracle

    # Download and extract fping-5.1
    cd /app
    wget https://fping.org/dist/fping-5.1.tar.gz
    tar -xzf fping-5.1.tar.gz
    rm fping-5.1.tar.gz

    # Apply perturbations
    chmod -x /app/fping-5.1/configure
    sed -i '10i CC_BROKEN = 1' /app/fping-5.1/src/Makefile.am

    # Create oracle script
    cat << 'EOF' > /opt/oracle/uptime_parser_oracle.py
#!/usr/bin/env python3
import sys, re
for line in sys.stdin:
    if 'interactive-prompt>' in line:
        continue
    match = re.search(r'([a-fA-F0-9\.\:]+)\s*:\s*xmt/rcv/%loss\s*=\s*\d+/\d+/(\d+)%', line)
    if match:
        print(f"{match.group(1)},{match.group(2)}")
EOF
    chmod +x /opt/oracle/uptime_parser_oracle.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
