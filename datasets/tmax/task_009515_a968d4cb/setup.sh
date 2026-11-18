#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create logs directory and files
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.csv
timestamp,ip_address,status,username
2023-10-01T10:00:00Z,192.168.1.100,FAILED,admin
2023-10-01T10:05:00Z,192.168.1.100,FAILED,root
2023-10-01T10:10:00Z,192.168.1.100,FAILED,user
2023-10-01T10:15:00Z,192.168.1.100,FAILED,test
2023-10-01T10:20:00Z,10.0.0.5,FAILED,guest
2023-10-01T10:21:00Z,10.0.0.5,FAILED,guest
2023-10-01T10:22:00Z,10.0.0.5,FAILED,guest
2023-10-01T10:23:00Z,10.0.0.5,FAILED,guest
2023-10-01T10:24:00Z,10.0.0.5,FAILED,guest
2023-10-01T10:25:00Z,172.16.0.50,FAILED,admin
2023-10-01T10:26:00Z,172.16.0.50,FAILED,admin
2023-10-01T10:27:00Z,172.16.0.50,SUCCESS,admin
2023-10-01T10:28:00Z,invalid-ip-string,FAILED,hacker
2023-10-01T10:29:00Z,999.999.999.999,FAILED,hacker
EOF

    cat << 'EOF' > /home/user/logs/app.jsonl
{"ts": "2023-10-01T10:00:00Z", "level": "INFO", "msg": "System startup complete"}
{"ts": "2023-10-01T10:16:00Z", "level": "ERROR", "msg": "Connection timeout from origin 192.168.1.100 on port 8080"}
{"ts": "2023-10-01T10:17:00Z", "level": "WARN", "msg": "High memory usage detected from 10.0.0.5"}
{"ts": "2023-10-01T10:28:00Z", "level": "ERROR", "msg": "Database query failed, source: 172.16.0.50"}
{"ts": "2023-10-01T10:30:00Z", "level": "ERROR", "msg": "Unknown payload received from 10.0.0.5"}
EOF

    useradd -m -s /bin/bash user || true

    # Ensure Rust is available for the user
    cp -r /root/.cargo /home/user/
    cp -r /root/.rustup /home/user/
    chown -R user:user /home/user/.cargo /home/user/.rustup

    echo 'export PATH="/home/user/.cargo/bin:$PATH"' >> /home/user/.bashrc

    chmod -R 777 /home/user
