#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo binutils
pip3 install pytest

mkdir -p /app /home/user/data /home/user/telemetry_parser/src

# Create the Oracle (in Rust, then compiled and stripped)
cat << 'EOF' > /tmp/oracle.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let data = fs::read(&args[1]).unwrap();
    parse(&data, 0, data.len());
}

fn parse(data: &[u8], mut offset: usize, end: usize) {
    while offset + 3 <= end && offset + 3 <= data.len() {
        let ptype = data[offset];
        let len = (data[offset+1] as usize) | ((data[offset+2] as usize) << 8);
        offset += 3;

        if offset + len > end || offset + len > data.len() {
            break; // Corrupted length, gracefully stop parsing this level
        }

        if ptype == 1 {
            println!("{}\"type\":\"SensorData\",\"length\":{}{}", "{", len, "}");
        } else if ptype == 2 {
            println!("{}\"type\":\"Container\",\"length\":{}{}", "{", len, "}");
            if len > 0 {
                parse(data, offset, offset + len);
            }
        }
        offset += len;
    }
}
EOF
rustc /tmp/oracle.rs -o /app/telemetry_oracle -C opt-level=3
strip /app/telemetry_oracle
rm /tmp/oracle.rs

# Create the buggy Rust parser for the agent
cat << 'EOF' > /home/user/telemetry_parser/Cargo.toml
[package]
name = "telemetry_parser"
version = "0.1.0"
edition = "2021"
EOF

cat << 'EOF' > /home/user/telemetry_parser/src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { 
        eprintln!("Usage: {} <file>", args[0]);
        return; 
    }
    let data = fs::read(&args[1]).expect("Failed to read file");
    parse(&data, 0, data.len());
}

fn parse(data: &[u8], mut offset: usize, end: usize) {
    while offset + 3 <= end {
        let ptype = data[offset];
        let len = (data[offset+1] as usize) | ((data[offset+2] as usize) << 8);
        offset += 3;

        // BUG 1: Missing bounds check for corrupted length -> Panics!
        let _payload = &data[offset..offset+len]; 

        if ptype == 1 {
            println!("{}\"type\":\"SensorData\",\"length\":{}{}", "{", len, "}");
        } else if ptype == 2 {
            println!("{}\"type\":\"Container\",\"length\":{}{}", "{", len, "}");
            // BUG 2: If len is 0, this causes infinite loop because offset doesn't advance meaningfully.
            parse(data, offset, offset + len);
        }
        offset += len;
    }
}
EOF

# Generate dummy test data (with a 0-length container and a corrupted length)
cat << 'EOF' > /tmp/gen_data.py
import struct
with open('/home/user/data/packets.bin', 'wb') as f:
    # Valid SensorData
    f.write(struct.pack('<B H', 1, 4) + b'AAAA')
    # Valid Container with nested SensorData
    f.write(struct.pack('<B H', 2, 7) + struct.pack('<B H', 1, 4) + b'BBBB')
    # Infinite loop trigger: Container with length 0
    f.write(struct.pack('<B H', 2, 0))
    # Out of bounds trigger: SensorData with length exceeding file
    f.write(struct.pack('<B H', 1, 5000) + b'C')
EOF
python3 /tmp/gen_data.py

# Create hidden test data for verification
cat << 'EOF' > /tmp/gen_hidden.py
import struct
with open('/home/user/hidden_test_packets.bin', 'wb') as f:
    f.write(struct.pack('<B H', 1, 2) + b'XX')
    f.write(struct.pack('<B H', 2, 0))
    f.write(struct.pack('<B H', 1, 60000) + b'Y')
    f.write(struct.pack('<B H', 1, 2) + b'ZZ')
EOF
python3 /tmp/gen_hidden.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
