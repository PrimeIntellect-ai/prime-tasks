#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/extracted

    cat << 'EOF' > /home/user/dataset.carch
FILE: ../../../home/user/secret.txt
SIZE: 12
ENCODING: shift_jis
DATA: eJzzyC9JLMgvSS1e2KhdVKndKAUAMlAHOA==
FILE: valid_data/records.csv
SIZE: 9
ENCODING: shift_jis
DATA: eJzzSy1XyFTIVMhU0CjSAwAiJwQk
EOF

    chmod -R 777 /home/user
