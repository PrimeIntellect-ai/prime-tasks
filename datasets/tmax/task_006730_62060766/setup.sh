#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/staging /home/user/repo

    cat << 'EOF' > /home/user/config.json
{"min_level": 3, "allowed_prefix": "CORE"}
EOF

    cat << 'EOF' > /home/user/staging/file1.wal
[START]
LEVEL: 5
PREFIX: CORE
PAYLOAD: SGVsbG8gV29ybGQ=
[END]
[START]
LEVEL: 2
PREFIX: CORE
PAYLOAD: YmFkIGxldmVs
[END]
[START]
LEVEL: 4
PREFIX: EDGE
PAYLOAD: YmFkIHByZWZpeA==
[END]
EOF

    cat << 'EOF' > /home/user/staging/file2.wal
[START]
LEVEL: 3
PREFIX: CORE
PAYLOAD: VmFsaWQgUGF5bG9hZCAy
[END]
[START]
LEVEL: 5
PREFIX: CORE
PAYLOAD: SW5jb21wbGV0ZSBkYXRh
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
