#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.utf8
[2023-10-01 12:00:00] user1 :: WRITE -> /data/fileA.txt;/data/fileB.txt
[2023-10-01 12:05:00] user2 :: READ -> /data/fileA.txt
[2023-10-01 12:10:00] user1 :: WRITE -> /data/fileB.txt;/data/fileC.txt;/data/fileD.txt
[2023-10-01 12:15:00] user3 :: WRITE -> /data/fileB.txt;/data/fileD.txt
[2023-10-01 12:20:00] user4 :: WRITE -> /data/fileE.txt
[2023-10-01 12:25:00] user2 :: READ -> /data/fileC.txt;/data/fileE.txt
[2023-10-01 12:30:00] user5 :: WRITE -> /data/fileA.txt;/data/fileB.txt
EOF

    iconv -f UTF-8 -t UTF-16LE /home/user/raw_logs.utf8 > /home/user/legacy_audit.log
    rm /home/user/raw_logs.utf8

    chmod -R 777 /home/user
