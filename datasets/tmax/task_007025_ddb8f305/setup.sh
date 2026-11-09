#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/ci_logs
    mkdir -p /home/user/packet_parser/src
    mkdir -p /home/user/verifier

    cat << 'EOF' > /home/user/ci_logs/ci_failure.log
[INFO] Running tests...
test test_process_packet_valid ... ok
test test_process_packet_invalid_magic ... ok
test test_fuzz_random_inputs ... FAILED

failures:

---- test_fuzz_random_inputs stdout ----
thread 'test_fuzz_random_inputs' panicked at 'byte index 7 is out of bounds of `&[u8]`', src/lib.rs:7:24
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace

failures:
    test_fuzz_random_inputs

test result: FAILED. 2 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out
EOF

    cat << 'EOF' > /home/user/packet_parser/Cargo.toml
[package]
name = "packet_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/packet_parser/src/lib.rs
pub fn process_packet(data: &[u8]) -> Result<u32, &'static str> {
    if data.is_empty() { return Err("Empty"); }
    if data[0] != 0xAA { return Err("Bad magic"); }
    if data.len() < 3 { return Err("Too short"); }

    let length = data[1] as usize;
    // Extract payload based on header length
    let payload = &data[2..2 + length];

    if payload.len() >= 4 {
        let val = u32::from_be_bytes([payload[0], payload[1], payload[2], payload[3]]);
        return Ok(val);
    }

    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_packet_valid() {
        assert_eq!(process_packet(&[0xAA, 0x04, 0x00, 0x00, 0x00, 0x2A]).unwrap(), 42);
    }

    #[test]
    fn test_process_packet_invalid_magic() {
        assert!(process_packet(&[0xBB, 0x04, 0x00, 0x00, 0x00, 0x2A]).is_err());
    }
}
EOF

    cat << 'EOF' > /home/user/verifier/verify.sh
#!/bin/bash

# Check reproducer
HEX=$(cat /home/user/reproducer.txt | tr -d ' \n\r')
if [[ ! "$HEX" =~ ^[0-9A-Fa-f]+$ ]]; then
    echo "reproducer.txt must be valid hex"
    exit 1
fi

# We won't rigorously check the hex string mathematically, but just ensuring it exists and the code is fixed is the main part.
# The code fix check:
cd /home/user/packet_parser

# Append a test to lib.rs to ensure the specific fix was applied
cat << 'TEST' >> src/lib.rs

#[test]
fn test_verify_out_of_bounds_fix() {
    assert_eq!(process_packet(&[0xAA, 0xFF, 0x00, 0x00]), Err("Out of bounds"));
}
TEST

cargo test > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Pass"
    exit 0
else
    echo "Fail"
    exit 1
fi
EOF
    chmod +x /home/user/verifier/verify.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
