#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create base directories
    mkdir -p /home/user/backup_source/projects/alpha
    mkdir -p /home/user/backup_source/archive/old
    mkdir -p /home/user/backup_source/docs

    # Create normal files and a valid symlink
    echo "Project Alpha Data" > /home/user/backup_source/projects/alpha/data.txt
    echo "Old Archive" > /home/user/backup_source/archive/old/data.txt
    echo "Docs" > /home/user/backup_source/docs/readme.md
    ln -s /home/user/backup_source/docs/readme.md /home/user/backup_source/projects/alpha/readme_link.md

    # Create problematic infinite symlinks
    ln -s /home/user/backup_source/projects /home/user/backup_source/projects/alpha/loop_to_projects
    ln -s /home/user/backup_source /home/user/backup_source/archive/old/loop_to_root

    # Create config file
    cat << 'EOF' > /home/user/backup_config.ini
[archive]
source_dir = /home/user/backup_source
output_file = /home/user/successful_backup.tar.gz
format = tar.gz
on_loop_detect = remove_link
EOF

    # Create log file
    cat << 'EOF' > /home/user/failed_backup.log
[ERROR] 2023-10-25 10:00:00 Backup Failed
Task: Archiving
Reason: File system loop detected
Path: /home/user/backup_source/projects/alpha/loop_to_projects
Detail: Symbolic link points to a parent directory.
--
[WARN] 2023-10-25 10:00:05 High memory usage
Task: Archiving
Detail: Memory spiked to 85% during tree traversal.
--
[ERROR] 2023-10-25 10:00:10 Backup Failed
Task: Archiving
Reason: File system loop detected
Path: /home/user/backup_source/archive/old/loop_to_root
Detail: Symbolic link points to a parent directory.
--
[INFO] 2023-10-25 10:00:15 Backup Aborted
Task: Cleanup
Detail: Temporary files removed.
EOF

    # Set permissions
    chmod -R 777 /home/user
