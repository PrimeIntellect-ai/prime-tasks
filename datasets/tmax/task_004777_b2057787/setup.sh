#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/ticket-db/data
    cd /home/user/ticket-db
    cargo init --bin

    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;

fn parse_wal(data: &[u8]) -> Vec<String> {
    let mut cursor = 4; // Skip magic bytes "TKDB"
    let mut records = Vec::new();

    while cursor < data.len() {
        // Bug: panics if cursor + 4 > data.len()
        let len_bytes: [u8; 4] = data[cursor..cursor+4].try_into().unwrap();
        let len = u32::from_le_bytes(len_bytes) as usize;
        cursor += 4;

        // Bug: panics if cursor + len > data.len()
        let record_bytes = &data[cursor..cursor+len];
        let record = String::from_utf8(record_bytes.to_vec()).unwrap();
        records.push(record);

        cursor += len;
    }
    records
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 && args[1] == "export" {
        let wal_data = fs::read("data/wal.dat").expect("Failed to read wal.dat");
        let records = parse_wal(&wal_data);
        for rec in records {
            println!("{}", rec);
        }
    } else {
        println!("Usage: ticket-db export");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_wal() {
        let mut data = b"TKDB".to_vec();
        let record = b"{\"id\":1}";
        data.extend_from_slice(&(record.len() as u32).to_le_bytes());
        data.extend_from_slice(record);

        let parsed = parse_wal(&data);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0], "{\"id\":1}");
    }
}
EOF

    python3 -c '
import struct

magic = b"TKDB"
records = [
    b"{\"id\": 1, \"desc\": \"Login issue\"}",
    b"{\"id\": 2, \"desc\": \"Mouse broken\"}",
    b"{\"id\": 3, \"desc\": \"Server down\"}"
]

with open("data/wal.dat", "wb") as f:
    f.write(magic)
    for r in records:
        f.write(struct.pack("<I", len(r)))
        f.write(r)

    # Write a corrupted record: length is 50, but only 5 bytes of data
    f.write(struct.pack("<I", 50))
    f.write(b"{\"id\":")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/ticket-db
    chmod -R 777 /home/user
