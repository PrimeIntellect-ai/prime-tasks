#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/cold_storage

    cat << 'EOF' > /home/user/raw_logs/fragment_alpha.raw
REPORT_DATE=2023-01-10
Some random binary or text data
EOF

    cat << 'EOF' > /home/user/raw_logs/fragment_beta.raw
REPORT_DATE=2023-02-14
Some random binary or text data 2
EOF

    cat << 'EOF' > /home/user/raw_logs/fragment_gamma.raw
REPORT_DATE=2023-03-22
Some random binary or text data 3
EOF

    cat << 'EOF' > /home/user/raw_logs/fragment_delta.raw
REPORT_DATE=2023-04-01
Some random binary or text data 4
EOF

    cat << 'EOF' > /home/user/raw_logs/fragment_epsilon.raw
REPORT_DATE=2023-05-05
Some random binary or text data 5
EOF

    chown -R user:user /home/user/raw_logs /home/user/cold_storage
    chmod -R 777 /home/user
