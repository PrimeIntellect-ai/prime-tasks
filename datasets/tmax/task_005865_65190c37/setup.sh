#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo/binaries

    cat << 'EOF' > /home/user/logs/scan.log
Artifact: core-v1.bin
Build-Status: SUCCESS
Critical-Vulnerabilities: 0
Warnings: 5
---
Artifact: ui-v2.bin
Build-Status: SUCCESS
Critical-Vulnerabilities: 1
Warnings: 0
---
Artifact: db-v3.bin
Build-Status: FAILED
Critical-Vulnerabilities: 0
Warnings: 2
---
Artifact: auth-v1.bin
Build-Status: SUCCESS
Critical-Vulnerabilities: 0
Warnings: 1
---
Artifact: cache-v4.bin
Build-Status: SUCCESS
Critical-Vulnerabilities: 0
Warnings: 0
EOF

    touch /home/user/incoming/core-v1.bin
    touch /home/user/incoming/ui-v2.bin
    touch /home/user/incoming/db-v3.bin
    touch /home/user/incoming/auth-v1.bin
    touch /home/user/incoming/cache-v4.bin

    cat << 'EOF' > /home/user/repo/manifest.txt
core-v1.bin | PENDING | 1670000000
ui-v2.bin | PENDING | 1670000010
db-v3.bin | PENDING | 1670000020
auth-v1.bin | PENDING | 1670000030
cache-v4.bin | PENDING | 1670000040
legacy-v1.bin | APPROVED | 1660000000
EOF

    chown -R user:user /home/user/logs /home/user/incoming /home/user/repo
    chmod -R 777 /home/user
