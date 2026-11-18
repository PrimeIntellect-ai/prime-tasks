#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/reference_data.csv
id,reference_value
1,10
2,12
3,15
4,18
5,20
EOF

    espeak -w /app/measurements.wav "Eighty two, eighty five, eighty eight, ninety, ninety one"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
