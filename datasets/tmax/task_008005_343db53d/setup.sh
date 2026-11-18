#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/config_2023-10-01.txt
port 8080
MAX_CONNECTIONS 100
timeout 30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-02.txt
port 8080
max_connections 0x64
timeout 30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-03.txt
port 8080
Max_Connections 120
timeout 30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-04.txt
port 8080
MAX_CONNECTIONS 0x82
timeout 30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-05.txt
port 8080
max_connections 200
timeout 30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-06.txt
port 8080
MAX_CONNECTIONS 210
timeout 30
EOF

    chmod -R 777 /home/user
