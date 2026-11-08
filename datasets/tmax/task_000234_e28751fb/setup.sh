#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_log.py
import os

log_path = "/home/user/fleet_audit.log"

with open(log_path, "w") as f:
    f.write("System boot...\n")
    f.write("Warning: memory low\n")

    # Record 1
    f.write("@@@ CONFIG_START | HOST: web_01 | TIME: 1690000000 @@@\n")
    f.write("server {\n  listen 80;\n  server_name example.com;\n}\n")
    f.write("@@@ CONFIG_END @@@\n")

    f.write("Some random garbage log line here.\n")

    # Record 2
    f.write("@@@ CONFIG_START | HOST: db_master | TIME: 1690000500 @@@\n")
    f.write("max_connections=500\nshared_buffers=2GB\n")
    f.write("@@@ CONFIG_END @@@\n")

    # Record 3 (Multi-line complex)
    f.write("@@@ CONFIG_START | HOST: cache_node | TIME: 1690001000 @@@\n")
    for i in range(50):
        f.write(f"bind 192.168.1.{i}\n")
    f.write("@@@ CONFIG_END @@@\n")
EOF
    python3 /home/user/setup_log.py
    rm /home/user/setup_log.py

    chmod -R 777 /home/user
