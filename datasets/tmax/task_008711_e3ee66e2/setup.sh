#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data
    cd /home/user/audit_data

    # Create original uncorrupted logs
    echo "Event ID: 1001, Status: SUCCESS, User: admin" > log_01.txt
    echo "Event ID: 1002, Status: FAILED, User: guest" > log_02.txt
    echo "Event ID: 1003, Status: SUCCESS, User: system" > log_03.txt

    # Generate expected hashes (ground truth)
    sha256sum log_*.txt > hashes.txt

    # Corrupt log_02.txt to simulate storage degradation
    echo 'Event ID: 1002, Status: CORRUPTED, User: g#e$t' > log_02.txt

    # Create the archive with the corrupted file
    tar -czf audit_backup.tar.gz log_01.txt log_02.txt log_03.txt

    # Encrypt the archive using the specific password
    openssl enc -aes-256-cbc -pbkdf2 -salt -in audit_backup.tar.gz -out audit_backup.enc -pass pass:ComplianceLog_2016

    # Clean up raw files leaving only the puzzle for the agent
    rm log_*.txt audit_backup.tar.gz

    # Create the hint file
    echo "All backup passwords follow the format: ComplianceLog_YYYY where YYYY is a year between 2010 and 2020." > key_policy.txt

    chmod -R 777 /home/user
