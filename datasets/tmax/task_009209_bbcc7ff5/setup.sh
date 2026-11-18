#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tar gzip zip unzip file
    pip3 install pytest

    mkdir -p /home/user/backups/extracted
    cd /home/user/backups

    # Create first log file
    cat << 'EOF' > app1.log
[INFO] Application started
[DEBUG] Initializing modules

[ERROR] 2023-10-15T10:00:00Z
Database connection failed
Host: 10.0.0.5
Retrying in 5 seconds...

[INFO] Retry successful
EOF

    # Create second log file
    cat << 'EOF' > hidden.log
[WARN] High memory usage
[ERROR] 2023-10-15T11:20:00Z
Unhandled exception in worker thread
NullReferenceException at processRequest
Client IP: 172.16.254.1
Stack trace ends.

[INFO] Shutting down
EOF

    # Create third log file
    cat << 'EOF' > regular.log
[ERROR] Critical failure
Timeout reaching 192.168.100.22
EOF

    # Archive hidden.log into a gzip without extension
    gzip -c hidden.log > blob_alpha
    # Archive regular.log into a zip without extension
    zip -q blob_beta.zip regular.log
    mv blob_beta.zip blob_beta

    # Create the main archive
    tar -czf raw.tar.gz app1.log blob_alpha blob_beta
    rm app1.log hidden.log regular.log blob_alpha blob_beta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
