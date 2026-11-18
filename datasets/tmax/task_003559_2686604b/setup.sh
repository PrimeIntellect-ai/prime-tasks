#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
plaintext = b"The secret flag is: FLAG{tr4c1ng_4nd_d3bugg1ng_rust_c0d3}"
ciphertext = bytearray()
state = 0xAF
for b in plaintext:
    enc = b ^ state
    ciphertext.append(enc)
    state = (state + enc) & 0xFF

with open("/home/user/evidence.enc", "wb") as f:
    f.write(ciphertext)
EOF
    python3 /tmp/setup.py

    cd /home/user
    cargo new malware_decoder
    cd malware_decoder

    cat << 'EOF' > src/main.rs
use std::fs;

fn decrypt(data: &mut Vec<u8>) {
    let mut state: u8 = 0xAF;
    for i in 0..data.len() {
        let encrypted_byte = data[i];

        // Decrypt the byte
        data[i] ^= state;

        // BUG: The state should be updated using the encrypted_byte, not the decrypted data[i]
        state = state.wrapping_add(data[i]); 

        // Malware's internal integrity check
        if i == 50 {
            assert_eq!(data[i], b'u', "Integrity check failed at byte 50");
        }
    }
}

fn main() {
    let mut data = fs::read("/home/user/evidence.enc").expect("Failed to read evidence.enc");
    decrypt(&mut data);
    fs::write("/home/user/decrypted.txt", &data).expect("Failed to write decrypted.txt");
    println!("Decryption successful.");
}
EOF

    chmod -R 777 /home/user
