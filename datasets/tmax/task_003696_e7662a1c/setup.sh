#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/legacy_project/data
    mkdir -p /home/user/legacy_project/src/logs
    mkdir -p /home/user/legacy_project/backup/archives

    # Create dummy file for valid archives
    echo "Sample data for valid archives" > /tmp/dummy.txt

    # Create valid ZIP
    cd /tmp && zip /home/user/legacy_project/data/good_data.zip dummy.txt

    # Create corrupt ZIP (just text disguised as zip)
    echo "This is not a valid zip file format, it will fail integrity checks." > /home/user/legacy_project/backup/archives/broken_backup.zip

    # Create valid TAR.GZ
    cd /tmp && tar -czf /home/user/legacy_project/backup/archives/safe_backup.tar.gz dummy.txt

    # Create corrupt TAR.GZ (just text disguised as tar.gz)
    echo "This is also not a valid tar.gz file format." > /home/user/legacy_project/data/corrupted_data.tar.gz

    # Create stale log files (mtime before Jan 1, 2023)
    touch -d "2022-05-01 12:00:00" /home/user/legacy_project/src/logs/old_app.log
    touch -d "2021-12-31 23:59:59" /home/user/legacy_project/data/legacy.log

    # Create fresh log files (mtime on or after Jan 1, 2023)
    touch -d "2023-05-01 12:00:00" /home/user/legacy_project/src/logs/new_app.log
    touch -d "2023-01-01 00:00:00" /home/user/legacy_project/backup/archives/recent_backup.log

    # Cleanup
    rm /tmp/dummy.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
