#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/waf_pipeline/rust_sanitizer/src
    mkdir -p /home/user/waf_pipeline/python_scanner

    cat << 'EOF' > /home/user/waf_pipeline/rust_sanitizer/Cargo.toml
[package]
name = "rust_sanitizer"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/waf_pipeline/rust_sanitizer/src/lib.rs
#[no_mangle]
pub extern "C" fn sanitize_payload(ptr: *mut u8, len: usize) -> usize {
    unsafe {
        let slice = std::slice::from_raw_parts_mut(ptr, len);
        let mut data = slice.to_vec();

        // Bug: borrowing data immutably while mutating it later
        let first_byte = &data[0];

        // Decode simple ROT-1 encoding (simulated decoding)
        for i in 0..data.len() {
            data[i] = data[i].wrapping_sub(1);
        }

        // Mutating data
        data.push(0);

        // Using the immutable borrow after mutation (causes borrow checker error)
        if *first_byte == 0 {
            return 0;
        }

        slice.copy_from_slice(&data[..len]);
        len
    }
}
EOF

    cat << 'EOF' > /home/user/waf_pipeline/python_scanner/vm.py
class WAFEmulator:
    def __init__(self, bytecode):
        self.bytecode = bytecode
        self.stack = []
        self.pc = 0

    def run(self):
        while self.pc < len(self.bytecode):
            opcode = self.bytecode[self.pc]
            self.pc += 1

            if opcode == 0x00: # HALT
                break
            elif opcode == 0x01: # PUSH
                val = self.bytecode[self.pc]
                self.stack.append(val)
                self.pc += 1
            elif opcode == 0x02: # ADD
                b = self.stack.pop()
                a = self.stack.pop()
                self.stack.append((a + b) & 0xFF)
            elif opcode == 0x03: # XOR
                # TODO: Implement XOR
                pass
            else:
                pass
        return self.stack
EOF

    cat << 'EOF' > /home/user/waf_pipeline/python_scanner/scanner.py
import ctypes
import base64
import os
from vm import WAFEmulator

# Load Rust library
lib_path = os.path.join(os.path.dirname(__file__), "librust_sanitizer.so")
sanitizer = ctypes.CDLL(lib_path)

with open(os.path.join(os.path.dirname(__file__), "payload.b64"), "r") as f:
    encoded_payload = f.read().strip()

raw_bytes = bytearray(base64.b64decode(encoded_payload))
buffer = (ctypes.c_uint8 * len(raw_bytes))(*raw_bytes)

sanitizer.sanitize_payload(buffer, len(raw_bytes))
sanitized_bytes = bytes(buffer)

emulator = WAFEmulator(sanitized_bytes)
result_stack = emulator.run()

with open(os.path.join(os.path.dirname(os.path.dirname(__file__)), "scan_result.log"), "w") as f:
    f.write(f"RESULT: {result_stack}")
EOF

    cat << 'EOF' > /home/user/waf_pipeline/python_scanner/payload.b64
AisCEgQB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
