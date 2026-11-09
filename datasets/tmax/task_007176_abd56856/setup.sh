#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv cargo rustc
    pip3 install pytest

    mkdir -p /home/user/parser/src

    cat << 'EOF' > /home/user/parser/Cargo.toml
[package]
name = "parser"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/parser/src/lib.rs
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn decode_message(data: *const u8, len: usize) -> *mut c_char {
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    if len == 0 { return std::ptr::null_mut(); }

    let enc_type = slice[0];
    let payload = &slice[1..];

    let decoded = if enc_type == 0 {
        String::from_utf8_lossy(payload).into_owned()
    } else {
        let mut u16_slice = Vec::new();
        for chunk in payload.chunks_exact(2) {
            u16_slice.push(u16::from_le_bytes([chunk[0], chunk[1]]));
        }
        String::from_utf16_lossy(&u16_slice)
    };

    let c_str = CString::new(decoded).unwrap();
    // BUG: Returns pointer to dropped memory
    c_str.as_ptr() as *mut c_char 
}
EOF

    cat << 'EOF' > /home/user/server.py
import asyncio
import websockets

async def handler(websocket):
    for i in range(99):
        # 0 = UTF-8 encoding
        payload = f"Message {i}".encode('utf-8')
        await websocket.send(b'\x00' + payload)
        await asyncio.sleep(0.001)

    # 100th message: UTF-16LE encoding
    final_str = "FINAL_TEST_MESSAGE_SUCCESS"
    payload_16 = final_str.encode('utf-16le')
    await websocket.send(b'\x01' + payload_16)

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    python3 -m venv /home/user/venv
    /home/user/venv/bin/pip install websockets

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
