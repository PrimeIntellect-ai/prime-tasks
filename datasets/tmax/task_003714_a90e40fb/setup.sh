#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tar gzip
    pip3 install pytest

    mkdir -p /home/user/setup_workspace/logs/a/b
    mkdir -p /home/user/setup_workspace/logs/c
    mkdir -p /home/user/setup_workspace/logs/d/e/f

    cat << 'EOF' > /home/user/setup_workspace/logs/a/1.txt
Project: Apollo
System booted.
Connecting to 192.168.1.15 for updates.
Secondary connection to 10.0.0.2 established.
EOF

    cat << 'EOF' > /home/user/setup_workspace/logs/a/b/2.txt
Project: Gemini
No network connection required.
EOF

    cat << 'EOF' > /home/user/setup_workspace/logs/c/3.txt
Project: Apollo
Error connecting to 172.16.254.1. Retrying.
EOF

    cat << 'EOF' > /home/user/setup_workspace/logs/d/e/f/4.txt
Project: Artemis
Launch sequence initiated.
Client IP: 8.8.8.8
Backup IP: 8.8.4.4
Localhost: 127.0.0.1
EOF

    cd /home/user/setup_workspace
    tar -czf /home/user/incoming_logs.tar.gz logs/
    cd /home/user
    rm -rf /home/user/setup_workspace

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
