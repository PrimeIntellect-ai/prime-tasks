#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file tar coreutils bash gawk grep findutils
    pip3 install pytest

    mkdir -p /home/user/backups/archives
    mkdir -p /home/user/backups/logs
    mkdir -p /home/user/backups/data/projA
    mkdir -p /home/user/backups/data/projB
    mkdir -p /home/user/backups/notes

    # Create archives
    echo "Valid data 1" > /tmp/valid1.txt
    tar -czf /home/user/backups/archives/backup_valid_1.tar.gz -C /tmp valid1.txt
    echo "Valid data 2" > /tmp/valid2.txt
    tar -czf /home/user/backups/archives/backup_valid_2.tar.gz -C /tmp valid2.txt

    # Create corrupted archives
    dd if=/dev/urandom of=/home/user/backups/archives/backup_corrupt_1.tar.gz bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=/home/user/backups/archives/backup_corrupt_2.tar.gz bs=1K count=1 2>/dev/null

    # Create job_history.log
    cat << 'EOF' > /home/user/backups/logs/job_history.log
Job ID: 1001
Date: 2023-10-01
Status: SUCCESS
---
Job ID: 1002
Date: 2023-10-02
Status: FAILED
Error: Disk full
---
Job ID: 1003
Date: 2023-10-03
Status: FAILED
Error: Network timeout
---
Job ID: 1004
Date: 2023-10-04
Status: SUCCESS
---
EOF

    # Create files in data (ELF and normal)
    echo "Just a text file" > /home/user/backups/data/projA/readme.md
    cp /bin/ls /home/user/backups/data/projA/tool.bin
    cp /bin/bash /home/user/backups/data/projB/runner.exe
    echo "More text" > /home/user/backups/data/projB/data.dat

    # Create ISO-8859-1 notes
    echo -ne "Backup note 1: r\xe9sum\xe9\n" > /home/user/backups/notes/note1.txt
    echo -ne "Backup note 2: jalape\xf1o\n" > /home/user/backups/notes/note2.txt
    echo -ne "Backup note 3: fa\xe7ade\n" > /home/user/backups/notes/note3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
