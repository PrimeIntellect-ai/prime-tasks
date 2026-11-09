#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The disk quota has been exceeded on the primary storage volume. Please allocate additional drives to the RAID array immediately to prevent data loss."

    mkdir -p /home/user/transcripts
    mkdir -p /home/user/syslogs
    mkdir -p /home/user/archive_dir

    cat << 'EOF' > "/home/user/syslogs/server 1.log"
[INFO] System booted
[DEBUG] Checking memory mapping
[ERROR] Disk space low
[DEBUG] Reallocating sectors
EOF

    cat << 'EOF' > "/home/user/syslogs/app server.log"
[INFO] App started
[DEBUG] Loading config
[INFO] Connected to DB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
