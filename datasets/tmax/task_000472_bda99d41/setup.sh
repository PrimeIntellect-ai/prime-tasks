#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-setuptools
    pip3 install pytest

    mkdir -p /app/vendored/mail-sender-v2/mail_sender
    mkdir -p /app/corpora/evil /app/corpora/clean

    cat << 'EOF' > /app/vendored/mail-sender-v2/setup.py
from setuptools import setup, find_packages
setup(
    name='mail-sender-v2',
    version='2.0.0',
    packages=find_packages(),
    install_requires=['requests' 'urllib3']
)
EOF

    cat << 'EOF' > /app/vendored/mail-sender-v2/mail_sender/__init__.py
__version__ = '2.0.0'
EOF

    cat << 'EOF' > /app/vendored/mail-sender-v2/mail_sender/connection.py
import os
def connect():
    port = os.environ['MAIL_PORT_OVERRIDE']
    return f"Connected on {port}"
EOF

    cat << 'EOF' > /app/corpora/clean/paths.txt
/mnt/backup_restores/db_backup_2023.tar
/mnt/backup_restores/user_data/home.zip
/mnt/backup_restores/weekly_snapshot_01
/mnt/backup_restores/app_logs_archived
EOF

    cat << 'EOF' > /app/corpora/evil/paths.txt
/mnt/backup_restores/../etc/shadow
/mnt/backup_restores/db backup.tar
/mnt/backup_restores/db_backup.tar;rm -rf /
/tmp/other_directory/backup.tar
/mnt/backup_restores/short
/mnt/backup_restores/$(whoami)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
