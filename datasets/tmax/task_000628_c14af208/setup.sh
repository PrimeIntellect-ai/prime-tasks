#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/processed_csv
    mkdir -p /tmp/backup_gen/dirA
    mkdir -p /tmp/backup_gen/dirB
    mkdir -p /tmp/backup_gen/dirC

    cat << 'EOF' > /tmp/backup_gen/dirA/file1.json
[
  {"id": 5, "name": "Alice", "timestamp": "2023-01-01"},
  {"id": 12, "name": "Bob", "timestamp": "2023-01-02"}
]
EOF

    cat << 'EOF' > /tmp/backup_gen/dirB/file2.json
[
  {"id": 8, "name": "Charlie", "timestamp": "2023-01-03"},
  {"id": 1, "name": "Dave", "timestamp": "2023-01-04"}
]
EOF

    cat << 'EOF' > /tmp/backup_gen/dirC/file3.json
[
  {"id": 15, "name": "Eve", "timestamp": "2023-01-05"},
  {"id": 3, "name": "Frank", "timestamp": "2023-01-06"},
  {"id": 9, "name": "Grace", "timestamp": "2023-01-07"}
]
EOF

    cd /tmp/backup_gen
    ln -s ../dirB dirA/link_to_B
    ln -s ../dirA dirB/link_to_A
    ln dirA/file1.json dirC/file1_hardlink.json

    tar -czvf /tmp/raw_backup.tar.gz *
    # Use split size of 150 bytes to ensure partab is created
    split -b 150 /tmp/raw_backup.tar.gz /home/user/backups/raw_backup.tar.gz.part
    rm -rf /tmp/backup_gen /tmp/raw_backup.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
