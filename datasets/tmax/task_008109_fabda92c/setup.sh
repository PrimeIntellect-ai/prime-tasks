#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/storage-node/src
    cd /home/user/storage-node

    cat << 'EOF' > Cargo.toml
[package]
name = "storage-node"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/models.rs
pub struct DataBlockV1 {
    pub id: u32,
    pub payload: Vec<u8>,
}

pub struct DataBlockV2 {
    pub id: u32,
    pub payload: Vec<u8>,
    pub checksum: u8,
}

// TODO: Implement From<DataBlockV1> for DataBlockV2

// TODO: Implement is_valid(&self) -> bool for DataBlockV2
EOF

    cat << 'EOF' > src/main.rs
mod models;
use models::{DataBlockV1, DataBlockV2};

fn process_legacy_block(v1: DataBlockV1) -> DataBlockV2 {
    // This requires From<DataBlockV1> for DataBlockV2 to be implemented
    DataBlockV2::from(v1)
}

fn main() {
    let v1 = DataBlockV1 {
        id: 101,
        payload: vec![10, 20, 30], // XOR sum: 10 ^ 20 ^ 30 = 00001010 ^ 00010100 = 00011110 (30) ^ 30 = 0
    };

    let v2 = process_legacy_block(v1);

    if v2.is_valid() {
        println!("Migration and validation successful for block {}", v2.id);
    } else {
        println!("Validation failed!");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_migration_and_checksum() {
        let v1 = DataBlockV1 {
            id: 42,
            payload: vec![1, 2, 3, 4, 5], // 1^2^3^4^5 = 1
        };
        let v2: DataBlockV2 = v1.into();
        assert_eq!(v2.id, 42);
        assert_eq!(v2.checksum, 1);
        assert!(v2.is_valid());
    }

    #[test]
    fn test_invalid_block() {
        let mut v2 = DataBlockV2 {
            id: 43,
            payload: vec![1, 2, 3],
            checksum: 0,
        };
        // 1^2^3 = 0, so initially valid
        assert!(v2.is_valid());
        // Mutate payload to simulate corruption
        v2.payload[0] = 99;
        assert!(!v2.is_valid());
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
