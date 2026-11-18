#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Setup Rust project
    mkdir -p /home/user/web_service/src
    cd /home/user/web_service
    cat << 'EOF' > Cargo.toml
[package]
name = "web_service"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::fs;

pub fn read_user_file(filename: &str) -> Result<String, String> {
    // VULNERABLE: No sanitization, susceptible to Path Traversal (CWE-22)
    let path = format!("/tmp/public_uploads/{}", filename);
    fs::read_to_string(&path).map_err(|e| e.to_string())
}

fn main() {
    println!("Web service starting...");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_file() {
        // Mock valid file read
        assert!(read_user_file("test.txt").is_err()); // Will error because file doesn't exist, which is fine
    }

    #[test]
    fn test_path_traversal_blocked() {
        assert_eq!(read_user_file("../../../etc/passwd"), Err("Invalid filename".to_string()));
        assert_eq!(read_user_file("folder/file.txt"), Err("Invalid filename".to_string()));
    }
}
EOF

    # 2. Setup SSH config
    mkdir -p /home/user/ssh_audit
    cat << 'EOF' > /home/user/ssh_audit/sshd_config
# Insecure SSH Config
Port 22
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
EOF

    # 3. Setup SSH keys with bad permissions
    mkdir -p /home/user/ssh_keys
    echo "FAKE PRIVATE KEY DATA" > /home/user/ssh_keys/id_rsa

    chmod -R 777 /home/user
