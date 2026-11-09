#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake make gcc patch
    pip3 install pytest websockets

    mkdir -p /home/user/math_utils/build

    cat << 'EOF' > /home/user/math_utils/mathops.c
#include <math.h>

double newton_sqrt(double n, int iterations) {
    double x = n;
    for(int i=0; i<iterations; i++) {
        x = x + n / x; // BUGGY LOGIC
    }
    return x;
}
EOF

    cat << 'EOF' > /home/user/math_utils/fix_math.patch
--- mathops.c
+++ mathops.c
@@ -5,3 +5,3 @@
     for(int i=0; i<iterations; i++) {
-        x = x + n / x; // BUGGY LOGIC
+        x = 0.5 * (x + n / x); // CORRECT LOGIC
     }
EOF

    cat << 'EOF' > /home/user/math_utils/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathUtils)

add_library(mathops SHARED mathops.c)
EOF

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import ctypes
import os

# Ensure the library path matches where the agent is instructed to build it
lib_path = os.path.abspath('/home/user/math_utils/build/libmathops.so')
lib = ctypes.CDLL(lib_path)
lib.newton_sqrt.restype = ctypes.c_double
lib.newton_sqrt.argtypes = [ctypes.c_double, ctypes.c_int]

async def handler(websocket):
    async for message in websocket:
        try:
            val = float(message)
            # 10 iterations of Newton-Raphson is sufficient for convergence here
            res = lib.newton_sqrt(val, 10)
            await websocket.send(str(res))
        except Exception as e:
            await websocket.send(f"Error: {e}")

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math_utils
    chown user:user /home/user/ws_server.py
    chmod -R 777 /home/user
