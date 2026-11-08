#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/staging
    mkdir -p /home/user/repo

    # Create artifacts using Python for precise binary header generation
    python3 -c '
import os
with open("/home/user/staging/core_sys.bin", "wb") as f:
    f.write(b"XBIN\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
with open("/home/user/staging/net_utils.bin", "wb") as f:
    f.write(b"ZPKG\x2A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
'

    # Append random payloads
    dd if=/dev/urandom of=/tmp/payload1 bs=1024 count=250 2>/dev/null
    cat /tmp/payload1 >> /home/user/staging/core_sys.bin
    dd if=/dev/urandom of=/tmp/payload2 bs=1024 count=105 2>/dev/null
    cat /tmp/payload2 >> /home/user/staging/net_utils.bin

    chmod -R 777 /home/user
