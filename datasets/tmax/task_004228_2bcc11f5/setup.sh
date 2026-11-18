#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/server.log
10.0.0.1 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1234
192.168.14.88 - - [10/Oct/2023:13:56:01 +0000] "GET /login.php?user=admin' UNION SELECT 1,2,3-- HTTP/1.1" 200 450
192.168.14.88 - - [10/Oct/2023:13:56:05 +0000] "POST /upload.php HTTP/1.1" 200 900
10.0.0.2 - - [10/Oct/2023:13:57:00 +0000] "GET /about.html HTTP/1.1" 200 800
172.16.5.4 - - [10/Oct/2023:13:58:12 +0000] "GET /login.php?user=admin' UNION SELECT 1,2,3-- HTTP/1.1" 403 210
EOF

    echo -n "SYSTEM_BACKUP_START FLAG{b4sh_x0r_m4st3r} SYSTEM_BACKUP_END" | xxd -p | tr -d '\n' | fold -w2 | while read hex; do
        printf "%02x" "$(( 0x$hex ^ 0x5A ))"
    done > /home/user/evidence/blob.hex

    chmod -R 777 /home/user
