#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_target

    # Create file1 (Safe: Correct permissions, correct hash)
    echo "Sensitive configuration data line 1" > /home/user/audit_target/config_alpha.conf

    # Create file2 (Violation: Incorrect permissions, but correct hash)
    echo "User credentials backup" > /home/user/audit_target/users_backup.dat

    # Create file3 (Compromised: Incorrect permissions AND mismatched hash)
    echo "Service endpoint list" > /home/user/audit_target/endpoints.txt

    # Original content hash generation
    sha256sum /home/user/audit_target/endpoints.txt > /home/user/hashes.sha256
    sha256sum /home/user/audit_target/config_alpha.conf >> /home/user/hashes.sha256
    sha256sum /home/user/audit_target/users_backup.dat >> /home/user/hashes.sha256

    # Now modify the compromised file
    echo "203.0.113.45" >> /home/user/audit_target/endpoints.txt
    echo "MALICIOUS_ENTRY" >> /home/user/audit_target/endpoints.txt
    echo "198.51.100.99" >> /home/user/audit_target/endpoints.txt

    # Set general permissions
    chmod -R 777 /home/user

    # Fix specific file permissions required by the task
    chmod 600 /home/user/audit_target/config_alpha.conf
    chmod 644 /home/user/audit_target/users_backup.dat
    chmod 666 /home/user/audit_target/endpoints.txt
