#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/data /home/user/output

    # Create initial files
    cat << 'EOF' > /home/user/data/config_v1.json
{
  "Server-Port": "8080",
  "DB_Host": "localhost",
  "log-level": "INFO",
  "Max-Connections": "100"
}
EOF

    cat << 'EOF' > /home/user/data/config_v2.csv
key,value
server-port,8081
db_host,localhost
LOG-LEVEL,DEBUG
max-connections,150
enable-cache,true
EOF

    cat << 'EOF' > /home/user/data/config_v3.ini
[default]
Server_Port=8081
db-host=127.0.0.1
log_level=WARN
max_connections=150
enable_cache=false
timeout=30
EOF

    # Make rust available for all users
    cp -r $HOME/.cargo /home/user/.cargo
    cp -r $HOME/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    # Set permissions
    chmod -R 777 /home/user
