#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup/v1
    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/backup/v1/server.json
{
  "port": 8080,
  "host": "localhost",
  "enabled": true,
  "protocol": "http"
}
EOF

    cat << 'EOF' > /home/user/configs/server.json
{
  "port": 8081,
  "host": "localhost",
  "enabled": true,
  "timeout": 30
}
EOF

    cat << 'EOF' > /home/user/backup/v1/users.csv
id,name,role
1,admin,root
2,john,user
EOF

    cat << 'EOF' > /home/user/configs/users.csv
id,name,role
1,admin,root
3,alice,user
EOF

    chmod -R 777 /home/user
