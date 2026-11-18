#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/auth_service/src

    cat << 'EOF' > /home/user/auth_service/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /api/data?key=a1b2c3d4e5 HTTP/1.1" 401 15
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "GET /api/data?key=testkey123 HTTP/1.1" 401 15
172.16.0.4 - - [10/Oct/2023:13:58:12 -0700] "GET /api/data?key=f9b8c7d6e5 HTTP/1.1" 200 120
192.168.1.15 - - [10/Oct/2023:14:01:22 -0700] "GET /api/data?key=admin123 HTTP/1.1" 401 15
EOF

    cat << 'EOF' > /home/user/auth_service/src/main.rs
use sha256::digest;

fn validate_api_key(key: &str) -> bool {
    // Legacy implementation
    false
}

fn validate_backup_password(pass: &str) -> bool {
    let hash = digest(pass);
    // Hardcoded credentials vulnerability
    hash == "361bc1575239e2469dd17dc3e1eeaa09787e9c933b93f2f84cf1360ecb38c238"
}

fn main() {
    println!("Auth service starting...");
}
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin
password
qwerty
hunter2
iloveyou
letmein123
backup2023
supersecret
EOF

    chmod -R 777 /home/user
