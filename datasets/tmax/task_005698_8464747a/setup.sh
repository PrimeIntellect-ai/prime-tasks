#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest websockets

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/math_ext.c
#include <stdlib.h>

double calculate_variance(double* data, int length) {
    double sum = 0.0, mean, variance = 0.0;
    for(int i=0; i<length; i++) sum += data[i];
    mean = sum / length;
    for(int i=0; i<length; i++) variance += (data[i] - mean) * (data[i] - mean);
    return variance / length;
}
EOF

    cat << 'EOF' > /home/user/workspace/server.py
import asyncio
import websockets
import json
import ctypes
import os

# FFI configuration missing
math_lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), "libmath.so"))
# math_lib.calculate_variance.argtypes = ...
# math_lib.calculate_variance.restype = ...

async def handler(websocket):
    async for message in websocket:
        req = json.loads(message)
        if req['op'] == 'variance':
            data = req['data']
            length = len(data)
            arr_type = ctypes.c_double * length
            arr = arr_type(*data)
            result = math_lib.calculate_variance(arr, length)
            await websocket.send(json.dumps({"result": result}))

async def main():
    async with websockets.serve(handler, "localhost", 8080):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
