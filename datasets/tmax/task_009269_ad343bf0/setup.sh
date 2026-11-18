#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest grpcio grpcio-tools

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    mkdir -p /home/user/project/rust_lib/src

    cat << 'EOF' > /home/user/project/rust_lib/Cargo.toml
[package]
name = "processor"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/project/rust_lib/src/lib.rs
#[no_mangle]
pub extern "C" fn process_buffer(input: *const u8, len: usize, output: *mut u8) {
    if input.is_null() || output.is_null() {
        return;
    }

    let in_slice = unsafe { std::slice::from_raw_parts(input, len) };
    let mut out_slice = unsafe { std::slice::from_raw_parts_mut(output, len) };

    // Borrow checker bug: borrowing in_slice mutably while it's an immutable reference 
    // or holding multiple mutable references in a conflicting way.
    // We will just create a basic lifetime/borrow error.
    let mut temp_val = 0u8;
    let ref1 = &mut temp_val;
    let ref2 = &mut temp_val; // ERROR

    for i in 0..len {
        *ref1 = in_slice[i].wrapping_add(5);
        out_slice[i] = *ref2; 
    }
}
EOF

    cat << 'EOF' > /home/user/project/compute.proto
syntax = "proto3";

package compute;

service ComputeService {
  rpc ProcessData (ProcessRequest) returns (ProcessResponse) {}
}

message ProcessRequest {
  bytes payload = 1;
}

message ProcessResponse {
  bytes result = 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
