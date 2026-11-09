#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/wal_parser/src
    mkdir -p /home/user/wal_parser/test_data

    cat << 'EOF' > /home/user/wal_parser/Cargo.toml
[package]
name = "wal_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/wal_parser/src/lib.rs
#[derive(Debug, PartialEq)]
pub enum Error {
    UnexpectedEof,
}

pub fn parse_wal(data: &[u8]) -> Result<usize, Error> {
    let mut offset = 0;
    let mut count = 0;

    while offset < data.len() {
        // We assume at least 5 bytes for type + length, but the code doesn't check!
        if offset + 5 > data.len() {
            return Err(Error::UnexpectedEof);
        }

        let _rec_type = data[offset];
        offset += 1;

        let len = u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap()) as usize;
        offset += 4;

        // BUG: Panics if offset + len > data.len()
        let _payload = &data[offset..offset + len];
        offset += len;

        count += 1;
    }

    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_corrupt_wal() {
        let data = std::fs::read("test_data/journal.wal").unwrap();
        let result = parse_wal(&data);
        assert_eq!(result, Err(Error::UnexpectedEof));
    }
}
EOF

    python3 -c '
with open("/home/user/wal_parser/test_data/journal.wal", "wb") as f:
    for _ in range(42):
        f.write(b"\x01\x04\x00\x00\x00ABCD")
    f.write(b"\x02\xff\xff\x00\x001234567890")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
