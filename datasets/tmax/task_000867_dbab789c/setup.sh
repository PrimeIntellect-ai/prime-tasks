#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/logs/log_a.txt
[INFO] 192.168.1.10 - System started
[DEBUG] 10.0.0.5 - Initializing modules
[INFO] 172.16.0.2 - User admin logged in
[DEBUG] 192.168.1.10 - Querying database
[ERROR] 8.8.8.8 - DNS resolution failed
EOF

    for i in {1..40}; do
      echo "[INFO] 192.168.1.$i - Action $i completed" >> /home/user/logs/log_a.txt
      echo "[DEBUG] 10.0.0.$i - Debug info $i" >> /home/user/logs/log_a.txt
    done

    cat << 'EOF' > /home/user/logs/log_b.txt
[WARNING] 10.10.10.10 - High memory usage
[INFO] 127.0.0.1 - Health check passed
EOF

    for i in {41..100}; do
      echo "[INFO] 192.168.1.$i - Action $i completed" >> /home/user/logs/log_b.txt
      echo "[DEBUG] 10.0.0.$i - Debug info $i" >> /home/user/logs/log_b.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
