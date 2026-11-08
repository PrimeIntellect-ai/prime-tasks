#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark gdb sqlite3 xxd tcpdump cargo rustc libsqlite3-dev pkg-config gcc
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cargo new /home/user/db_recovery

    cat << 'EOF' > /home/user/db_recovery/src/parser.rs
pub fn parse_packet(data: &[u8]) -> Vec<u8> {
    if data.is_empty() { return vec![]; }
    let len = data[0] as usize;
    let mut out = vec![0; len];
    unsafe {
        // BUG: out of bounds read if len > data.len() - 1
        std::ptr::copy_nonoverlapping(data.as_ptr().add(1), out.as_mut_ptr(), len);
    }
    out
}
EOF

    cat << 'EOF' > /home/user/db_recovery/src/main.rs
mod parser;
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <payload.bin> <corrupted.wal>", args[0]);
        std::process::exit(1);
    }
    let payload = fs::read(&args[1]).unwrap();
    let _wal = fs::read(&args[2]).unwrap();

    // This will segfault with the malformed packet
    let _parsed = parser::parse_packet(&payload);

    // If we survive, create the recovered db
    let db_path = "/home/user/recovered.db";
    let conn = rusqlite::Connection::open(db_path).unwrap();
    conn.execute("CREATE TABLE IF NOT EXISTS secrets (recovery_key TEXT)", []).unwrap();
    conn.execute("INSERT INTO secrets (recovery_key) VALUES ('FLAG_RUST_GDB_RECOVERY_9921')", []).unwrap();
    println!("Database recovered to {}", db_path);
}
EOF

    sed -i '/\[dependencies\]/a rusqlite = { version = "0.29.0", features = ["bundled"] }' /home/user/db_recovery/Cargo.toml

    cd /home/user/db_recovery
    cargo fetch || true

    echo "WAL_DATA_DUMMY" > /home/user/corrupted.wal

    python3 -c "
from scapy.all import *
pkt = IP(dst='127.0.0.1')/UDP(dport=8888)/Raw(load=b'\xff\x01\x02\x03')
wrpcap('/home/user/traffic.pcap', pkt)
"

    chown -R user:user /home/user
    chmod -R 777 /home/user
