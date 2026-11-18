#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    cd /home/user/backups

    # Create valid JSON content
    cat << 'EOF' > valid1.json
{
  "name": "ServiceA",
  "port": 8080,
  "enabled": true
}
EOF

    cat << 'EOF' > valid2.json
{
  "database": {
    "host": "localhost",
    "timeout": 30
  }
}
EOF

    # Create invalid JSON content
    cat << 'EOF' > invalid1.json
{
  "name": "ServiceB"
  "port": 9090
}
EOF

    cat << 'EOF' > invalid2.json
{
  "retry_count": 5,
  "nodes": ["node1", "node2",]
}
EOF

    # Loose files
    mv valid1.json loose_valid1.json
    mv invalid1.json loose_invalid1.json

    # Archive 1: Valid zip with mixed JSONs
    mkdir archive1_dir
    mv valid2.json archive1_dir/archive1_valid2.json
    mv invalid2.json archive1_dir/archive1_invalid2.json
    cd archive1_dir
    zip -r ../backup1.zip ./*
    cd ..
    rm -rf archive1_dir

    # Archive 2: Corrupted zip containing a valid JSON
    mkdir archive2_dir
    cat << 'EOF' > archive2_dir/lost_valid.json
{"key": "value"}
EOF
    cd archive2_dir
    zip -r ../backup2_corrupt.zip ./*
    cd ..
    rm -rf archive2_dir
    # Corrupt the zip file
    dd if=/dev/urandom of=backup2_corrupt.zip bs=1024 count=1 conv=notrunc

    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
