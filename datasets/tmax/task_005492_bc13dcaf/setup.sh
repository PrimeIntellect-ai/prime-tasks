#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/auth.log
[08:12:01] AUTH: Authenticated TXN-1024
[08:12:05] AUTH: Authenticated TXN-3312
[08:12:10] AUTH: Authenticated TXN-8842
[08:12:15] AUTH: Authenticated TXN-9910
EOF

    cat << 'EOF' > /home/user/logs/router.log
[08:12:02] ROUTER: Routing TXN-1024 (size 150 bytes)
[08:12:06] ROUTER: Routing TXN-3312 (size 80 bytes)
[08:12:11] ROUTER: Routing TXN-8842 (size 12 bytes)
[08:12:16] ROUTER: Routing TXN-9910 (size 200 bytes)
EOF

    cat << 'EOF' > /home/user/logs/parser.log
[08:12:03] PARSER: Start processing TXN-1024
[08:12:03] PARSER: Finished processing TXN-1024 successfully
[08:12:07] PARSER: Start processing TXN-3312
[08:12:08] PARSER: Finished processing TXN-3312 successfully
[08:12:12] PARSER: Start processing TXN-8842
EOF

    mkdir -p /home/user/parser/src
    cat << 'EOF' > /home/user/parser/Cargo.toml
[package]
name = "parser"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/parser/src/main.rs
pub fn extract_payload(packet: &[u8]) -> &[u8] {
    if packet.len() < 2 { return &[]; }

    // header_len calculation formula: byte[0] + (byte[1] * 2)
    let header_len = packet[0] as usize + (packet[1] as usize * 2);

    // VULNERABILITY: Missing bounds check before unsafe slicing.
    // If header_len > packet.len(), packet.len() - header_len underflows
    unsafe {
        let ptr = packet.as_ptr().add(header_len);
        std::slice::from_raw_parts(ptr, packet.len() - header_len)
    }
}

fn main() {
    println!("Parser running...");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
