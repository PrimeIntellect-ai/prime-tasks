#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/artifacts/binaries

    # Create dummy artifact files
    echo -n "BIN_DATA_01" > /home/user/artifacts/binaries/app_v1.bin
    echo -n "BIN_DATA_02" > /home/user/artifacts/binaries/app_v2.bin
    echo -n "BIN_DATA_03" > /home/user/artifacts/binaries/app_v3.bin
    echo -n "BIN_DATA_04" > /home/user/artifacts/binaries/app_v4.bin

    # Create manifest
    cat << 'EOF' > /home/user/artifacts/manifest.txt
001 /home/user/artifacts/binaries/app_v1.bin 2023-01-01 STALE
002 /home/user/artifacts/binaries/app_v2.bin 2023-02-01 ACTIVE
003 /home/user/artifacts/binaries/app_v3.bin 2023-01-15 STALE
004 /home/user/artifacts/binaries/missing.bin 2023-01-10 STALE
005 /home/user/artifacts/binaries/app_v4.bin 2023-01-05 STALE
EOF

    # Create initial index (app_v1.bin is already archived)
    echo "/home/user/artifacts/binaries/app_v1.bin" > /home/user/archive_index.txt

    # Create initial archive containing app_v1.bin
    python3 -c "
import struct
with open('/home/user/stale_archive.bin', 'wb') as f:
    path = b'/home/user/artifacts/binaries/app_v1.bin'
    f.write(path.ljust(256, b'\x00'))
    f.write(struct.pack('<Q', 11))
    f.write(b'BIN_DATA_01')
"
    chmod +x /home/user/artifacts/binaries/*.bin

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
