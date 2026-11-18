#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential binutils
    pip3 install pytest pytest-asyncio websockets

    mkdir -p /home/user/ws_calc/src
    mkdir -p /home/user/ws_calc/tests

    cat << 'EOF' > /home/user/ws_calc/src/libcalc.cpp
#include <vector>

// BUG: Missing extern C causing ABI mangling
void process_data(double* data, int size) {
    for(int i = 0; i < size; ++i) {
        data[i] *= 2.0;
    }
}
EOF

    cat << 'EOF' > /home/user/ws_calc/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(CalcProject)

set(CMAKE_CXX_STANDARD 14)

add_library(calc SHARED src/libcalc.cpp)
set_target_properties(calc PROPERTIES PREFIX "lib")
EOF

    cat << 'EOF' > /home/user/ws_calc/server.py
import asyncio
import websockets
import ctypes
import json
import sys
import os

# Ensure the path points to the expected CMake build output
lib_path = os.path.join(os.path.dirname(__file__), 'build', 'libcalc.so')
try:
    lib = ctypes.CDLL(lib_path)
except OSError as e:
    print(f"Failed to load library: {e}")
    sys.exit(1)

# Bug in cpp file causes this to fail unless fixed (AttributeError)
try:
    process_data_func = lib.process_data
    process_data_func.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
except AttributeError as e:
    print(f"ABI linking error: {e}")
    sys.exit(1)

async def handler(websocket):
    async for message in websocket:
        req = json.loads(message)
        data = req.get('data', [])
        if not data:
            continue

        arr = (ctypes.c_double * len(data))(*data)
        process_data_func(arr, len(data))

        await websocket.send(json.dumps({"result": list(arr)}))

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
