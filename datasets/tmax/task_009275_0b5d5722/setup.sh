#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar gzip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup environment
    mkdir -p /home/user/setup/backup/loop_dir
    cd /home/user/setup/backup/loop_dir
    ln -s . loop_link
    cd /home/user/setup/backup

    # Create binary files
    printf '\xef\xbe\xad\xde\x64\x00\x00\x00' > valid1.bin
    printf '\xef\xbe\xad\xde\xc8\x00\x00\x00' > valid2.bin
    printf '\x00\x00\x00\x00\x64\x00\x00\x00' > invalid.bin

    # Create JSON logs
    mkdir -p logs_dir/nested
    cat << 'EOF' > logs_dir/log1.json
[
  {"id": 105, "status": "ERROR", "message": "Disk full"},
  {"id": 102, "status": "OK", "message": "All good"}
]
EOF
    cat << 'EOF' > logs_dir/nested/log2.json
[
  {"id": 101, "status": "ERROR", "message": "Timeout"},
  {"id": 108, "status": "ERROR", "message": "Permission denied"}
]
EOF

    cd logs_dir
    zip -r ../logs.zip .
    cd ..
    rm -rf logs_dir

    cd /home/user/setup
    tar -czf /home/user/backup.tar.gz backup
    cd /home/user
    rm -rf /home/user/setup

    chmod -R 777 /home/user
