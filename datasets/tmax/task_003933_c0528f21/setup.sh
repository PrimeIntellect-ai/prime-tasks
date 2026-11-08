#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/config.txt
ARCHIVE_DIR=/home/user/backups
MAGIC_HEADER=RLE_V1
EOF

    cat << 'EOF' > /home/user/backups/backup1.rle
RLE_V1
5A3B
EOF

    cat << 'EOF' > /home/user/backups/backup2.rle
RLE_V1
5A3B
EOF

    cat << 'EOF' > /home/user/backups/backup3.rle
RLE_V1
2C
EOF

    cat << 'EOF' > /home/user/backups/backup4.rle
RLE_V2
5A3B
EOF

    cat << 'EOF' > /home/user/backups/backup5.rle
RLE_V1
5A3B
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
