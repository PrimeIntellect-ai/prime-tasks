#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import csv

data = [
    [1600000000, "server-1", "nginx_config", "worker_processes 1;\nevents {\n worker_connections 1024;\n}"], # 4 lines
    [1600000005, "server-2", "nginx_config", "worker_processes 2;\nevents {\n worker_connections 2048;\n}"], # 4 lines
    [1600000010, "server-1", "db_config", "port=3306\nmax_connections=100"], # Ignored
    [1600000020, "server-1", "nginx_config", "worker_processes 1;\nevents {\n worker_connections 1024;\n}\nhttp {\n sendfile on;\n}"], # 7 lines
    [1600000025, "server-3", "nginx_config", "worker_processes 4;\nevents {\n worker_connections 4096;\n}\nhttp {\n sendfile on;\n tcp_nopush on;\n}"], # 8 lines
    [1600000040, "server-1", "nginx_config", "worker_processes 2;\nevents {\n worker_connections 1024;\n}\nhttp {\n sendfile on;\n tcp_nopush on;\n}"], # 8 lines
    [1600000050, "server-2", "nginx_config", "worker_processes 2;\nevents {\n worker_connections 2048;\n}\nhttp {\n sendfile off;\n}"], # 7 lines
    [1600000060, "server-3", "nginx_config", "worker_processes 4;\n"], # 2 lines
    [1600000070, "server-3", "nginx_config", "worker_processes 4;\nevents {\n worker_connections 4096;\n}"], # 4 lines
]

with open('/home/user/audit_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Timestamp", "Server", "Key", "Value"])
    for row in data:
        writer.writerow(row)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
