#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/framing.rs
#[repr(C)]
pub struct WsFrame {
    pub fin: u8,
    pub opcode: u8,
    pub payload_len: usize,
    pub payload: *const u8,
}

#[no_mangle]
pub extern "C" fn generate_frame_bytes(frame: *const WsFrame, out_len: *mut usize) -> *mut u8 {
    let f = unsafe { &*frame };
    let mut buffer = Vec::new();
    buffer.push((f.fin << 7) | f.opcode);
    buffer.push(f.payload_len as u8); // simplified length logic for fuzzing

    let payload = unsafe { std::slice::from_raw_parts(f.payload, f.payload_len) };

    let buffer_ref = &buffer;
    buffer.extend_from_slice(payload);
    let _val = buffer_ref[0]; // intentional borrow checker bug here

    let mut boxed = buffer.into_boxed_slice();
    unsafe { *out_len = boxed.len() };
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    ptr
}
EOF

    cat << 'EOF' > /home/user/fuzzer.py
import ctypes
import binascii

# TODO: Define WsFrame ctypes Structure here to match the Rust struct
# WsFrame fields: fin (u8), opcode (u8), payload_len (usize), payload (pointer to u8)

def main():
    payload_data = b"TEST"

    # TODO: Load ./libframing.so

    # TODO: Setup argtypes and restype for generate_frame_bytes
    # signature: generate_frame_bytes(frame: *const WsFrame, out_len: *mut usize) -> *mut u8

    # TODO: Create WsFrame instance: fin=1, opcode=2, payload_len=len(payload_data), payload=payload_data

    # TODO: Call generate_frame_bytes

    # TODO: Read the returned bytes into a Python bytes object

    # TODO: Write the hex-encoded string of the bytes to /home/user/frame_output.hex
    pass

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
