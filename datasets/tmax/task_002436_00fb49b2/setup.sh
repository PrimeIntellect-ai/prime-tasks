#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg procps g++
    pip3 install pytest

    # Install MongoDB 7.0 and Database Tools
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update
    apt-get install -y mongodb-org mongodb-database-tools

    # Create task files
    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_dump.csv
sensor_id,location,temp,timestamp,status
S1,North,20.5,100,OK
S1,North,21.0,105,OK
S2,South,22.0,101,OK
S2,South,99.9,102,ERROR
S3,North,19.0,103,OK
S4,East,25.0,104,OK
S4,East,26.0,106,OK
EOF
    chmod 644 /home/user/sensor_dump.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
