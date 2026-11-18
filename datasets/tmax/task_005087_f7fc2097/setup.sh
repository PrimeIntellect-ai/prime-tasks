#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg build-essential
    pip3 install pytest aiohttp numpy

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Install MongoDB (mongod, mongosh)
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
       gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
       tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update && apt-get install -y mongodb-org

    # Create directories
    mkdir -p /home/user/analytics_service/src

    # Create dummy Rust files
    cat << 'EOF' > /home/user/analytics_service/Cargo.toml
[package]
name = "analytics_service"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
warp = "0.3"
mongodb = "2.8"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/analytics_service/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/analytics_service/src/queries.rs
// Unoptimized queries
EOF

    # Create start_services.sh
    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
mkdir -p /data/db
mongod --fork --logpath /var/log/mongodb.log
EOF
    chmod +x /home/user/start_services.sh

    # Create verifier.py
    cat << 'EOF' > /home/user/verifier.py
import asyncio
import aiohttp
import time
import sys
import numpy as np

async def fetch(session, url):
    start = time.perf_counter()
    async with session.get(url) as response:
        await response.text()
    return time.perf_counter() - start

async def main():
    url = "http://127.0.0.1:8080/export?customer_id=CUST_123"
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, url) for _ in range(500)]
        times = await asyncio.gather(*tasks)

    p95 = np.percentile(times, 95)
    print(p95)

    # Check export file format
    try:
        with open("/home/user/results.ndjson", "r") as f:
            lines = f.readlines()
            if len(lines) == 0 or "total_spent" not in lines[-1]:
                sys.exit(1)
    except:
        sys.exit(1)

    if p95 <= 0.250:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
