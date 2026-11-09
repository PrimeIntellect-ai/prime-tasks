#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/rust-api/src

    cat << 'EOF' > /home/user/rust-api/src/main.rs
mod rate_limit;

fn main() {
    println!("API configured with rate limit: {}", rate_limit::LIMIT);
}
EOF

    cat << 'EOF' > /home/user/rust-api/build_and_run.sh
#!/bin/bash

# Extract and decode the rate limit setting
ENCODED_LIMIT="MTAw"

# Decode the limit and write to Rust file
echo "$ENCODED_LIMIT" | base64 -D > src/rate_limit.rs

# Compile the Rust project
rustc src/main.rs --out-dir bin/
EOF

    chmod +x /home/user/rust-api/build_and_run.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
