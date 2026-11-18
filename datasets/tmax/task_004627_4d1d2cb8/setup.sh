#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget jq
    pip3 install pytest websockets

    mkdir -p /home/user/.github/workflows

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import hashlib
import base64

def make_pkg(name, version, content, dep, tampered=False):
    b64_content = base64.b64encode(content.encode()).decode()
    real_hash = hashlib.sha256(content.encode()).hexdigest()
    if tampered:
        # Flip first character of hash to simulate tampering
        bad_char = 'a' if real_hash[0] != 'a' else 'b'
        reported_hash = bad_char + real_hash[1:]
    else:
        reported_hash = real_hash
    return f"PKG {name} {version} {reported_hash} {b64_content} {dep}"

packages = [
    make_pkg("core-lib", "1.0.0", "print('core 1.0.0')", "NONE", tampered=True),
    make_pkg("core-lib", "1.1.0", "print('core 1.1.0')", "NONE", tampered=False),
    make_pkg("core-lib", "1.2.0", "print('core 1.2.0')", "NONE", tampered=False),
    make_pkg("web-framework", "2.0.0", "print('web 2.0.0')", "core-lib=1.0.0", tampered=False),
    make_pkg("web-framework", "2.1.0", "print('web 2.1.0')", "core-lib=1.1.0", tampered=False),
    make_pkg("auth-plugin", "3.0.0", "print('auth 3.0.0')", "web-framework=2.1.0", tampered=False),
    make_pkg("auth-plugin", "3.1.0", "print('auth 3.1.0')", "web-framework=2.0.0", tampered=False),
]

async def handler(websocket):
    for pkg in packages:
        await websocket.send(pkg)
    await websocket.close()

async def main():
    async with websockets.serve(handler, "localhost", 9090):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    # To ensure the server is running during tests and for the agent
    echo "python3 /home/user/ws_server.py &" >> /etc/bash.bashrc
    echo "python3 /home/user/ws_server.py &" >> /home/user/.bashrc

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
