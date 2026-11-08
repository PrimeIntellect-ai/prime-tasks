#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils make
    pip3 install pytest websockets

    mkdir -p /home/user

    cat << 'EOF' > /home/user/artifact.json
{
  "schema_version": "1.2",
  "artifact_info": {
    "arch": "x86_64",
    "artifact_id": "FW-x86-092",
    "timestamp": 1698765432
  },
  "payload": {
    "instructions": [
      "mov rax, 60",
      "mov rdi, 187",
      "syscall"
    ]
  }
}
EOF

    cat << 'EOF' > /home/user/ws_harness.py
import asyncio
import websockets
import json
import sys

async def handler(websocket, path):
    try:
        message = await websocket.recv()
        data = json.loads(message)

        if data.get("artifact_id") == "FW-x86-092" and data.get("exit_code") == 187:
            with open("/home/user/verification.log", "w") as f:
                f.write("E2E_SUCCESS: Valid payload and exit code received.\n")
            await websocket.send('{"status": "verified"}')
        else:
            with open("/home/user/verification.log", "w") as f:
                f.write(f"E2E_FAILURE: Invalid data {data}\n")
            await websocket.send('{"status": "rejected"}')
    except Exception as e:
        print(f"Error: {e}")

async def main():
    server = await websockets.serve(handler, "localhost", 8765)
    await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod +x /home/user/ws_harness.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
