#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest websockets packaging

    # Install Rust in a globally accessible location
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/bin:${PATH}"

    mkdir -p /home/user/math_integration/rust_engine/src

    cat << 'EOF' > /home/user/math_integration/rust_engine/Cargo.toml
[package]
name = "rust_engine"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/math_integration/rust_engine/src/lib.rs
#[no_mangle]
pub extern "C" fn compute_sequence(n: u32) -> u64 {
    let mut seq = vec![1u64, 1u64];
    let s_ptr = &mut seq;

    for i in 2..=(n as usize) {
        // Borrow checker bug: cannot borrow `seq` as immutable because it is also borrowed as mutable
        let v = seq[i-1] + 2 * seq[i-2];
        s_ptr.push(v);
    }
    seq[n as usize]
}
EOF

    cat << 'EOF' > /home/user/math_integration/server.py
import asyncio
import websockets
import json
import ctypes
import os

# Load the rust library
lib_path = os.path.join(os.path.dirname(__file__), "rust_engine/target/debug/librust_engine.so")
math_lib = ctypes.CDLL(lib_path)
math_lib.compute_sequence.argtypes = [ctypes.c_uint32]
math_lib.compute_sequence.restype = ctypes.c_uint64

async def handler(websocket, path):
    async for message in websocket:
        data = json.loads(message)

        # Bug: Naive string comparison
        if data.get("version", "0.0.0") < "2.1.0":
            await websocket.send(json.dumps({"error": "Protocol version too low"}))
            continue

        n = data.get("n", 0)
        result = math_lib.compute_sequence(n)
        await websocket.send(json.dumps({"result": result}))

start_server = websockets.serve(handler, "localhost", 8765)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    cat << 'EOF' > /home/user/math_integration/test_client.py
import asyncio
import websockets
import json

async def run_client():
    # Connect to the server, send {"version": "10.0.0", "n": 20}
    # Write the result to /home/user/result.txt
    pass

if __name__ == "__main__":
    asyncio.run(run_client())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /opt/rust
    chmod -R 777 /home/user
