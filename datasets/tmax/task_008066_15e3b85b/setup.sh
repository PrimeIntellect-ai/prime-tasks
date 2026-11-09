#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/backup_data/folderA
    mkdir -p /home/user/backup_data/folderB

    # Create circular symlinks
    ln -s /home/user/backup_data/folderA /home/user/backup_data/folderB/link_to_A
    ln -s /home/user/backup_data/folderB /home/user/backup_data/folderA/link_to_B

    # Create log files
    cat << 'EOF' > /home/user/backup_data/folderA/db_backup.log
[2023-11-01] Starting database backup
Connected to DB.
[2023-11-02] Backup progressing
Writing to tape...
CRITICAL_FAILURE: Tape drive jammed.
Retrying...
[2023-11-03] Cleanup
EOF

    cat << 'EOF' > /home/user/backup_data/folderB/app_backup.log
[2023-11-01] Starting app backup
All files copied.
[2023-11-02] Verification
Checksums match.
EOF

    cat << 'EOF' > /home/user/backup_data/system.log
[2023-10-15] System update
[2023-10-16] Rebooting
Kernel panic...
CRITICAL_FAILURE on boot sector.
Please replace drive.
[2023-10-17] Maintenance mode
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
