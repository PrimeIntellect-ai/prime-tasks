#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file
    pip3 install pytest

    mkdir -p /home/user/storage_pool/logs
    mkdir -p /home/user/storage_pool/critical
    mkdir -p /home/user/storage_pool/intended

    cat << 'EOF' > /home/user/storage_pool/logs/extract.log
---
Time: 2023-10-25 14:00:01
Extracted-To: file_a.dat
Bytes: 500
Status: SUCCESS
---
Time: 2023-10-25 14:00:02
Extracted-To: ../critical/malicious_1.conf
Bytes: 200
Status: SUCCESS
---
Time: 2023-10-25 14:00:03
Extracted-To: ../critical/failed_hack.conf
Bytes: 0
Status: FAILED
---
Time: 2023-10-25 14:00:04
Extracted-To: ../critical/malicious_2.conf
Bytes: 150
Status: SUCCESS
---
Time: 2023-10-25 14:00:05
Extracted-To: data report 1.dat
Bytes: 1000
Status: SUCCESS
---
EOF

    echo -n "malicious content 1" | iconv -f UTF-8 -t UTF-16LE > /home/user/storage_pool/critical/malicious_1.conf
    echo -n "malicious content 2" | iconv -f UTF-8 -t UTF-16LE > /home/user/storage_pool/critical/malicious_2.conf
    echo -n "normal system config" > /home/user/storage_pool/critical/failed_hack.conf
    echo -n "legit root config" > /home/user/storage_pool/critical/system.conf

    echo "content A" > /home/user/storage_pool/intended/file_a.dat
    echo "content A" > "/home/user/storage_pool/intended/file b.dat"
    echo "content A" > /home/user/storage_pool/intended/file_c.dat

    echo "content B" > "/home/user/storage_pool/intended/data report 1.dat"
    echo "content B" > "/home/user/storage_pool/intended/data_report_2.dat"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/storage_pool
    chmod -R 777 /home/user
