#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the legacy verifier binary with hardcoded keys
    cat << 'EOF' > /tmp/legacy_verifier.rs
fn main() {
    let _key = "12345678901234567890123456789012";
    let _iv = "1234567890123456";
    println!("Verifier initialized.");
}
EOF
    rustc /tmp/legacy_verifier.rs -o /home/user/legacy_verifier
    rm /tmp/legacy_verifier.rs

    # 2. Create the encrypted policy file
    # Key hex: 3132333435363738393031323334353637383930313233343536373839303132
    # IV hex: 31323334353637383930313233343536
    echo -n "POLICY_STRICT_ENFORCEMENT_992" | openssl enc -aes-256-cbc -K 3132333435363738393031323334353637383930313233343536373839303132 -iv 31323334353637383930313233343536 -out /home/user/policy.enc

    # 3. Create the vulnerable Rust project
    cd /home/user
    cargo new auth_server
    cat << 'EOF' > /home/user/auth_server/src/main.rs
pub fn get_redirect_url(input: &str) -> String {
    // Legacy redirect logic
    input.to_string()
}

fn main() {
    let url = get_redirect_url("http://evil.com");
    println!("Redirecting to: {}", url);
}
EOF

    chmod -R 777 /home/user
