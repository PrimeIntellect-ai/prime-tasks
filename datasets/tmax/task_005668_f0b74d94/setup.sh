#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest

    mkdir -p /home/user/source_data/app1
    mkdir -p /home/user/source_data/app2

    cat << 'EOF' > /home/user/source_data/app1/server.log
INFO: Starting server
API_KEY=A1B2C3D4E5
DEBUG: Connection established
EOF

    cat << 'EOF' > /home/user/source_data/app2/database.log
WARN: Retrying connection
API_KEY=9988776655QWERTY
ERROR: Timeout
EOF

    cat << 'EOF' > /home/user/source_data/app1/readme.txt
This is a documentation file.
Example key usage:
API_KEY=EXAMPLEKEY123
Do not redact this file.
EOF

    cd /home/user
    tar -czf raw_data.tar.gz source_data
    rm -rf source_data

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
