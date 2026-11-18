#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_logs

    cat << 'EOF' > /home/user/project_logs/sync.conf
target=/home/user/project_logs/consolidated.log
sources=logA.cst,logB.cst,logC.cst
EOF

    echo -n "MzITIGJvSBCdyRTMiBPOXRuRW9GT" > /home/user/project_logs/logA.cst
    echo -n "=...uRhdEIgNzaW5jZX9QBiBPOXRuRW9GT" > /home/user/project_logs/logB.cst
    echo -n "==wzITIGJvS QgbmVFOOXRuRW9GT" > /home/user/project_logs/logC.cst

    chown -R user:user /home/user/project_logs
    chmod -R 777 /home/user
