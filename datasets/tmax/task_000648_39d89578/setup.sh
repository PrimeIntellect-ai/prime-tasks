#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the attacker certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/attacker.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=malicious-c2.local"

    # Create the malware Rust source
    cat << 'EOF' > /tmp/malware.rs
use std::fs;

fn main() {
    let key = b"KEY_X0R_M4st3r!";
    let input = b"CRITICAL_EXFIL:root_password_hash_dumped";
    let mut output = Vec::new();

    for (i, &byte) in input.iter().enumerate() {
        output.push(byte ^ key[i % key.len()]);
    }

    fs::write("/home/user/evidence.enc", output).unwrap();
}
EOF

    # Compile and run the malware to generate evidence.enc
    rustc /tmp/malware.rs -o /home/user/malware
    /home/user/malware

    # Cleanup
    rm /tmp/malware.rs /tmp/key.pem

    chmod -R 777 /home/user
