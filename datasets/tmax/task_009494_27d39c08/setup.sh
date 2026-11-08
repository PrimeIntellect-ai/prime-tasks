#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev cargo rustc
    pip3 install pytest

    mkdir -p /home/user/legacy
    mkdir -p /home/user/firmware_decoder/src

    cat << 'EOF' > /home/user/legacy/libfirmware.c
#include <stdint.h>
#include <stddef.h>

// External logging callback expected from the host
extern void host_log_msg(const char* msg);

// TLV payload containing the bytecode
// Type 0x01: Dummy metadata
// Type 0x02: Bytecode (The real payload)
// Type 0x03: Footer
static const uint8_t firmware_data[] = {
    // Record 1: Metadata
    0x01, 0x04, 0x00, 0xBE, 0xEF, 0xCA, 0xFE,
    // Record 2: Bytecode Payload
    // Assembly:
    // LOAD 0x48 (H) -> OUT
    // LOAD 0x65 (e) -> OUT
    // LOAD 0x6C (l) -> OUT
    // LOAD 0x6C (l) -> OUT
    // LOAD 0x6F (o) -> OUT
    // XOR 0x20 -> OUT (space)
    // LOAD 0x57 (W) -> OUT
    // LOAD 0x6F (o) -> OUT
    // LOAD 0x72 (r) -> OUT
    // LOAD 0x6C (l) -> OUT
    // LOAD 0x64 (d) -> OUT
    // LOAD 0x21 (!) -> OUT
    // HALT
    0x02, 0x19, 0x00, 
    0x10, 0x48, 0x20,
    0x10, 0x65, 0x20,
    0x10, 0x6C, 0x20,
    0x10, 0x6C, 0x20,
    0x10, 0x6F, 0x20,
    0x12, 0x4F, 0x20, // 0x6F ^ 0x4F = 0x20 (space)
    0x10, 0x57, 0x20,
    0x10, 0x6F, 0x20,
    0x10, 0x72, 0x20,
    0x10, 0x6C, 0x20,
    0x10, 0x64, 0x20,
    0x10, 0x21, 0x20,
    0xFF,
    // Record 3: Checksum
    0x03, 0x02, 0x00, 0x12, 0x34
};

size_t get_firmware_blob(unsigned char* out_buffer, size_t max_len) {
    host_log_msg("Retrieving firmware blob...");
    size_t len = sizeof(firmware_data);
    if (len > max_len) return 0;
    for (size_t i = 0; i < len; i++) {
        out_buffer[i] = firmware_data[i];
    }
    return len;
}
EOF

    gcc -shared -fPIC -o /home/user/legacy/libfirmware.so /home/user/legacy/libfirmware.c

    cat << 'EOF' > /home/user/firmware_decoder/Cargo.toml
[package]
name = "firmware_decoder"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/firmware_decoder/src/main.rs
// TODO: Implement the FFI bindings, resolve the linking issue, 
// parse the TLV, and write the emulator.

fn main() {
    println!("Start decoding process...");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
