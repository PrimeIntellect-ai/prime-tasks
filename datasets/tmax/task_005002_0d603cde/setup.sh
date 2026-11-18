#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rustup /opt/cargo

    # Make Rust available in the environment
    cat << 'EOF' > /.singularity.d/env/99-rust.sh
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
export PATH="/opt/cargo/bin:${PATH}"
EOF
    chmod +x /.singularity.d/env/99-rust.sh

    # Create directory for server data
    mkdir -p /home/user/server_data
    cd /home/user/server_data

    # Create data1.csv
    cat << 'EOF' > data1.csv
timestamp,server_name,log_message
2023-01-01T10:00:00Z,serverA,E-500: Failed connection from 192.168.1.15
2023-01-01T10:05:00Z,serverB,INFO: Normal operation
2023-01-01T10:10:00Z,serverA,E-500: Failed connection from 10.0.0.42
2023-01-01T10:12:00Z,serverC,E-500: Failed connection from 10.0.0.42
EOF

    # Create data2.csv
    cat << 'EOF' > data2.csv
timestamp,server_name,log_message
2023-01-01T10:15:00Z,serverC,E-400: Bad request from 172.16.0.5
2023-01-01T10:20:00Z,serverA,E-500: Failed connection from 192.168.1.15
2023-01-01T10:22:00Z,serverB,E-500: Failed connection from not.an.ip.address
EOF

    # Create data3.csv
    cat << 'EOF' > data3.csv
timestamp,server_name,log_message
2023-01-01T10:25:00Z,serverD,E-500: Failed connection from 8.8.8.8
2023-01-01T10:30:00Z,serverE,E-500: Failed connection from 256.256.256.256
2023-01-01T10:35:00Z,serverF,E-500: Failed connection from 10.1.2.3
EOF

    # Setup auto-start for the HTTP server so it runs during tests/execution
    cat << 'EOF' > /.singularity.d/env/99-start-server.sh
#!/bin/sh
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8123/data1.csv', timeout=1)" 2>/dev/null; then
    cd /home/user/server_data && nohup python3 -m http.server 8123 > /dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-start-server.sh

    # Create user
    useradd -m -s /bin/bash user || true

    chmod -R 777 /home/user
