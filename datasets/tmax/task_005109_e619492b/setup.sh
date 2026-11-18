#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl redis-server build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    # Create directories
    mkdir -p /home/user/app/sanitizer/src
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create .env
    cat << 'EOF' > /home/user/app/.env
REDIS_URL=redis://localhost:9999
BIND_ADDR=127.0.0.1:8081
EOF

    # Create startup.sh
    cat << 'EOF' > /home/user/app/startup.sh
#!/bin/bash
killall redis-server || true
killall sanitizer || true
source /home/user/app/.env
redis-server --daemonize yes
cd /home/user/app/sanitizer
cargo run --release &
EOF
    chmod +x /home/user/app/startup.sh

    # Create Cargo.toml
    cat << 'EOF' > /home/user/app/sanitizer/Cargo.toml
[package]
name = "sanitizer"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
warp = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
redis = "0.22"
regex = "1.7"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/app/sanitizer/src/main.rs
use warp::Filter;
use std::env;

#[tokio::main]
async fn main() {
    let bind_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let sanitize = warp::post()
        .and(warp::path("sanitize"))
        .and(warp::body::json())
        .map(|body: serde_json::Value| {
            // Buggy implementation
            warp::reply::json(&body)
        });

    let addr: std::net::SocketAddr = bind_addr.parse().unwrap();
    warp::serve(sanitize).run(addr).await;
}
EOF

    # Create corpus files
    echo '{"message": "hello"}' > /home/user/corpus/clean/1.json
    echo '{"message": "hello", "ssn": "123-45-6789"}' > /home/user/corpus/evil/1.json

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
