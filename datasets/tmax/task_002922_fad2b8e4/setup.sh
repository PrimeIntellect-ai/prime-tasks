#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_config_logs.txt
[1700000000] MAX_CONNS=100 192.168.1.15
[1700000050] MAX_CONNS=100 192.168.1.15
[1700001000] TIMEOUT=30 10.0.0.5
[1700003599] TIMEOUT=45 10.0.0.5
[1700003600] TIMEOUT=60 10.0.0.5
[1700005000] MAX_CONNS=200 192.168.1.15
[1700005100] MAX_CONNS=250 192.168.1.15
[1700007100] FEATURE_FLAG_X=true 172.16.0.42
[1700007199] FEATURE_FLAG_X=false 172.16.0.42
EOF

    chmod -R 777 /home/user
