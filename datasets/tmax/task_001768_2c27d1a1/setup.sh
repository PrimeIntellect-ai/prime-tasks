#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat gawk cargo rustc
    pip3 install pytest

    # Create app directories
    mkdir -p /app/router_template/src

    # Create start_legacy_vm.sh
    cat << 'EOF' > /app/start_legacy_vm.sh
#!/bin/bash
# Mocking a QEMU VM port forward for the legacy service
nohup socat TCP-LISTEN:9090,bind=127.0.0.1,reuseaddr,fork EXEC:"awk '{print \"LEGACY_OS_ACK: \"\$0; fflush()}'" > /dev/null 2>&1 &
EOF
    chmod +x /app/start_legacy_vm.sh

    # Create Cargo.toml
    cat << 'EOF' > /app/router_template/Cargo.toml
[package]
name = "router"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
EOF

    # Create main.rs
    cat << 'EOF' > /app/router_template/src/main.rs
// Basic skeleton for the agent
#[tokio::main]
async fn main() {
    println!("Router starting...");
    // Agent must implement HTTP on 8000 and TCP on 8001 here
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
