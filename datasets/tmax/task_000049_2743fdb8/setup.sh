#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    mkdir -p /home/user/data/dir_alpha
    mkdir -p /home/user/data/dir_beta
    mkdir -p /home/user/data/dir_gamma
    mkdir -p /home/user/data/dir_delta

    echo "alpha content" > /home/user/data/dir_alpha/file1.txt
    echo "beta content" > /home/user/data/dir_beta/file2.txt
    echo "gamma content" > /home/user/data/dir_gamma/file3.txt
    echo "delta content" > /home/user/data/dir_delta/file4.txt

    cat << 'EOF' > /home/user/backup_queue.log
BEGIN_JOB
JobID: 1001
Status: REQUIRED
Path: /home/user/data/dir_alpha
Priority: LOW
END_JOB
BEGIN_JOB
JobID: 1002
Priority: HIGH
Path: /home/user/data/dir_beta
Status: IGNORED
END_JOB
BEGIN_JOB
JobID: 1003
Priority: CRITICAL
Status: REQUIRED
Path: /home/user/data/dir_gamma
END_JOB
BEGIN_JOB
JobID: 1004
Path: /home/user/data/dir_delta
Status: COMPLETED
Priority: NORMAL
END_JOB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
