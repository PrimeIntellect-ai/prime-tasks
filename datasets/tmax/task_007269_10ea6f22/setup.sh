#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data/documents/reports
    mkdir -p /home/user/data/images
    mkdir -p /home/user/data/configs

    # Create files
    echo "Report 1" > /home/user/data/documents/reports/2023_Q1.txt
    echo "Report 2" > /home/user/data/documents/reports/2023_Q2.txt
    echo "Image data" > /home/user/data/images/photo.jpg

    # Create the infinite loop symlink
    ln -s /home/user/data /home/user/data/documents/reports/archive_link

    # Create the backup configuration file
    cat << 'EOF' > /home/user/backup.conf
[Backup]
source_dir = /home/user/data
dest_archive = /home/user/system_backup.tar.gz
exclude_ext = .tmp
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
