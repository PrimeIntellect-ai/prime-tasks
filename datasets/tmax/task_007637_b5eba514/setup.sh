#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline.json
{
  "link_binary": {
    "deps": ["compile_c", "compile_ui"],
    "expr": "DIV MUL 100 2 5"
  },
  "compile_c": {
    "deps": ["fetch_deps"],
    "expr": "ADD XOR 15 7 2"
  },
  "compile_ui": {
    "deps": ["fetch_deps", "generate_assets"],
    "expr": "SUB 50 MUL 4 5"
  },
  "fetch_deps": {
    "deps": [],
    "expr": "ADD 10 15"
  },
  "generate_assets": {
    "deps": [],
    "expr": "XOR 255 170"
  },
  "package_apk": {
    "deps": ["link_binary"],
    "expr": "MUL ADD 2 3 SUB 10 2"
  }
}
EOF

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets

async def handler(websocket, path="/"):
    try:
        async for message in websocket:
            with open("/home/user/ws_received.log", "a") as f:
                f.write(message + "\n")
    except Exception:
        pass

async def main():
    async with websockets.serve(handler, "localhost", 9999):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    # Ensure the server starts when the user environment is initialized
    echo "python3 /home/user/ws_server.py &" >> /home/user/.bashrc
    echo "python3 /home/user/ws_server.py &" >> /etc/bash.bashrc

    chmod -R 777 /home/user
