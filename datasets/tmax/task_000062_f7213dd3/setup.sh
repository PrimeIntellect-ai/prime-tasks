#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/config.json
{
  "source_file": "/home/user/firmware.bin",
  "chunk_size": 1000,
  "chunk_prefix": "part_",
  "dest_archive": "/home/user/repo/firmware_packaged.tar.gz"
}
EOF

    head -c 2500 /dev/urandom > /home/user/firmware.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
