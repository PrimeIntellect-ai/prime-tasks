#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /login HTTP/1.1" 200 1234
192.168.1.11 - - [10/Oct/2023:13:55:40 +0000] "POST /login HTTP/1.1" 302 -
192.168.1.11 - - [10/Oct/2023:13:55:42 +0000] "GET /dashboard HTTP/1.1" 200 4521
10.0.0.5 - - [10/Oct/2023:14:02:11 +0000] "GET /login?redirect=http://evil-attacker.com/steal?token=30693e382e3969716b692a2f26222769776b693b39223d22272e2c2e69716b692e38282a272a3f2e2f6936 HTTP/1.1" 302 -
10.0.0.5 - - [10/Oct/2023:14:02:15 +0000] "GET /admin HTTP/1.1" 200 8920
EOF

    cat << 'EOF' > /home/user/auth_lib.rs
pub fn encode_token(payload: &str) -> String {
    // A proprietary encoding scheme for "security"
    payload
        .bytes()
        .map(|b| format!("{:02x}", b ^ 0x4B))
        .collect::<String>()
}

pub fn is_valid(token: &str) -> bool {
    token.len() > 0 && token.len() % 2 == 0
}
EOF

    chmod -R 777 /home/user
