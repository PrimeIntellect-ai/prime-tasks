#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/raw_configs
    for i in $(seq 1 20); do
        num=$(printf "%02d" $i)
        cat <<EOF > /home/user/raw_configs/config_${num}.ini
[Server]
PORT=$((8000 + i))
HOST=localhost
[Log]
DEBUG=true
MAX_FILES=5
# random padding $RANDOM
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
