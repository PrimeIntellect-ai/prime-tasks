#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create policy note image
    convert -size 500x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'ALLOWED_MOUNT_PREFIX=/mnt/storage_pool_A'" /app/policy_note.png

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/1.log
[ARCHIVE_RECORD]
ID=101
MOUNT=/mnt/storage_pool_A/backup_01
SIZE=1048576
[END_RECORD]
EOF

    cat << 'EOF' > /app/corpus/clean/2.log
[ARCHIVE_RECORD]
ID=102
MOUNT=/mnt/storage_pool_A/subdir/backup_02
SIZE=2048
[END_RECORD]
[ARCHIVE_RECORD]
ID=103
MOUNT=/mnt/storage_pool_A/backup_03
SIZE=4096
[END_RECORD]
EOF

    # Create evil corpus
    # Path traversal
    cat << 'EOF' > /app/corpus/evil/1.log
[ARCHIVE_RECORD]
ID=201
MOUNT=/mnt/storage_pool_A/../etc/passwd
SIZE=1024
[END_RECORD]
EOF

    # Wrong prefix
    cat << 'EOF' > /app/corpus/evil/2.log
[ARCHIVE_RECORD]
ID=202
MOUNT=/mnt/storage_pool_B/backup_01
SIZE=1024
[END_RECORD]
EOF

    # Malformed (missing SIZE)
    cat << 'EOF' > /app/corpus/evil/3.log
[ARCHIVE_RECORD]
ID=203
MOUNT=/mnt/storage_pool_A/backup_04
[END_RECORD]
EOF

    # Garbage data outside records
    cat << 'EOF' > /app/corpus/evil/4.log
[ARCHIVE_RECORD]
ID=204
MOUNT=/mnt/storage_pool_A/backup_05
SIZE=1024
[END_RECORD]
GARBAGE DATA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
