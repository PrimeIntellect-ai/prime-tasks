#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget jq coreutils
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_sign.py
import sys
import json
import hashlib
import asyncio
import websockets

async def sign_artifact(artifact_name):
    # Calculate SHA256 of the artifact name (no trailing newline)
    checksum = hashlib.sha256(artifact_name.encode('utf-8')).hexdigest()

    payload = json.dumps({
        "artifact": artifact_name,
        "checksum": checksum
    })

    async with websockets.connect("ws://127.0.0.1:8765") as websocket:
        await websocket.send(payload)
        response_str = await websocket.recv()
        response = json.loads(response_str)

        if "signature" in response:
            print(response["signature"])
        else:
            print("Error:", response.get("error", "Unknown error"))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    asyncio.run(sign_artifact(sys.argv[1]))
EOF

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import json
import hashlib

async def handler(websocket, path):
    try:
        message = await websocket.recv()
        data = json.loads(message)

        artifact = data.get("artifact")
        checksum = data.get("checksum")

        expected_checksum = hashlib.sha256(artifact.encode('utf-8')).hexdigest()

        if checksum != expected_checksum:
            await websocket.send(json.dumps({"error": "Checksum mismatch"}))
            return

        # Mock signature generation
        signature = f"SIG-{expected_checksum}"
        await websocket.send(json.dumps({
            "status": "success",
            "signature": signature
        }))
    except Exception as e:
        await websocket.send(json.dumps({"error": str(e)}))

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod -R 777 /home/user
