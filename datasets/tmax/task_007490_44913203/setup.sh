#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl wget git golang-go
pip3 install pytest hypothesis

# Install Rust
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="/opt/rust/bin:${PATH}"
chmod -R 777 /opt/rust

# Setup directories
mkdir -p /home/user/polyglot_system/rust_encoder/src
mkdir -p /home/user/polyglot_system/go_encoder
mkdir -p /home/user/polyglot_system/lib
mkdir -p /home/user/polyglot_system/bin

# Rust setup
cat << 'EOF' > /home/user/polyglot_system/rust_encoder/Cargo.toml
[package]
name = "rust_encoder"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

cat << 'EOF' > /home/user/polyglot_system/rust_encoder/src/lib.rs
use std::ffi::CStr;
use std::os::raw::c_char;

// BUG: Missing FFI attributes and keywords
fn encode_hex(input: *const c_char, output: *mut c_char) {
    let c_str = unsafe {
        assert!(!input.is_null());
        CStr::from_ptr(input)
    };
    let str_slice = c_str.to_str().unwrap();
    let hex_str = hex::encode(str_slice);

    unsafe {
        std::ptr::copy_nonoverlapping(hex_str.as_ptr(), output as *mut u8, hex_str.len());
        *output.add(hex_str.len()) = 0;
    }
}
EOF

# Add hex dependency
cd /home/user/polyglot_system/rust_encoder && cargo add hex

# Go setup
cat << 'EOF' > /home/user/polyglot_system/go_encoder/main.go
package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"strings"
	"sync"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	input := os.Args[1]

	results := make(chan string, len(input))
	var wg sync.WaitGroup

	for _, char := range input {
		wg.Add(1)
		go func(c rune) {
			defer wg.Done()
			results <- hex.EncodeToString([]byte(string(c)))
		}(char)
	}

	// BUG: wg.Wait() and close(results) should be run in a separate goroutine
	wg.Wait()
	// close(results) is missing or misplaced, causing deadlock on ranging if not careful.
	// Actually, just ranging over it without closing will deadlock.

	var out []string
	// Deadlocks here if not closed
	for i := 0; i < len(input); i++ {
		out = append(out, <-results)
	}

	fmt.Print(strings.Join(out, ""))
}
EOF
cd /home/user/polyglot_system/go_encoder && go mod init go_encoder

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

# Ensure cargo is in the path for the user
echo 'export PATH="/opt/rust/bin:${PATH}"' >> /home/user/.bashrc
