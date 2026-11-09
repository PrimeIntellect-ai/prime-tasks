#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl tar
    pip3 install pytest

    mkdir -p /home/user/temp_src
    cd /home/user/temp_src

    # Create utils.rs (CWE-78)
    cat << 'EOF' > utils.rs
use std::process::Command;

pub fn ping_host(user_input: &str) {
    let output = Command::new("sh")
        .arg("-c")
        .arg(format!("ping -c 1 {}", user_input))
        .output()
        .expect("Failed to execute");
    println!("{:?}", output);
}
EOF

    # Create auth.rs (CWE-798)
    cat << 'EOF' > auth.rs
pub fn login(user: &str, pass: &str) -> bool {
    let db_pass = "SuperSecretAdmin123";
    if user == "admin" && pass == db_pass {
        return true;
    }
    false
}
EOF

    # Create main.rs (Benign)
    cat << 'EOF' > main.rs
mod auth;
mod utils;

fn main() {
    println!("App started.");
}
EOF

    # Archive and encrypt
    tar -cvf evidence.tar utils.rs auth.rs main.rs
    openssl enc -aes-256-cbc -pbkdf2 -salt -in evidence.tar -out /home/user/evidence.tar.enc -pass pass:compliance2024

    # Cleanup temp
    cd /home/user
    rm -rf /home/user/temp_src

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
