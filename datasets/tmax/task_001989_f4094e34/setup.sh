#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/backup_parts
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -gravity center -draw "text 0,0 'TOKEN: RECURSION_HALTED_4429'" /app/api_token.png

    cat << 'EOF' > /tmp/bloated_system.conf
[SYSTEM_CONFIG]
max_retries=5
timeout_seconds=30
log_level=DEBUG
enable_symlink_checks=true
backup_dir=/var/backups/
EOF

    for i in $(seq 1 50000); do
        cat << 'EOF' >> /tmp/bloated_system.conf
[SYSTEM_CONFIG]
max_retries=5
timeout_seconds=30
log_level=DEBUG
enable_symlink_checks=true
backup_dir=/var/backups/
EOF
    done

    cd /tmp
    tar -czf corrupt_backup.tar.gz bloated_system.conf
    split -b 200K corrupt_backup.tar.gz /app/backup_parts/corrupt_backup.tar.gz.part
    rm /tmp/bloated_system.conf /tmp/corrupt_backup.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
