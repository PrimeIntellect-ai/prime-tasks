#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/events.csv
date,raw_payload
2023-11-01,{"event": "S\u0045RV\u0045R_CR\u0041SH"}
2023-11-01,{"event": "NORM\u0041L_OP"}
2023-11-03,{"event": "S\u0045RV\u0045R_DOWN"}
2023-11-05,{"event": "D\u0041T\u0041B\u0041S\u0045_F\u0041IL"}
EOF

    chmod -R 777 /home/user
