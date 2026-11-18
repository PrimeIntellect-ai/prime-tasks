#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux libc-bin coreutils grep sed gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/extracted_logs
    touch /home/user/extraction_audit.log

    # Create raw content
    echo -n "System initialized normally." | iconv -t UTF-16LE > /tmp/raw1.bin
    echo -n "Warning: Disk usage high." | iconv -t ISO-8859-1 > /tmp/raw2.bin
    echo -n "All services running." | iconv -t WINDOWS-1252 > /tmp/raw3.bin

    # Build the archive
    cat << 'EOF' > /home/user/backup_archive.txt
[BEGIN_FILE]
Path: var/log/startup.log
Encoding: UTF-16LE
[DATA]
EOF
    cat /tmp/raw1.bin >> /home/user/backup_archive.txt
    echo "" >> /home/user/backup_archive.txt
    cat << 'EOF' >> /home/user/backup_archive.txt
[END_FILE]
[BEGIN_FILE]
Path: ../../../home/user/.ssh/authorized_keys
Encoding: ISO-8859-1
[DATA]
EOF
    cat /tmp/raw2.bin >> /home/user/backup_archive.txt
    echo "" >> /home/user/backup_archive.txt
    cat << 'EOF' >> /home/user/backup_archive.txt
[END_FILE]
[BEGIN_FILE]
Path: /var/spool/mail/admin/status.txt
Encoding: WINDOWS-1252
[DATA]
EOF
    cat /tmp/raw3.bin >> /home/user/backup_archive.txt
    echo "" >> /home/user/backup_archive.txt
    cat << 'EOF' >> /home/user/backup_archive.txt
[END_FILE]
EOF

    chmod 644 /home/user/backup_archive.txt
    chown -R user:user /home/user/
    chmod -R 777 /home/user
