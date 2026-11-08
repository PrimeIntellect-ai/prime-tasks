#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python2 bc wget
pip3 install pytest websockets

wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl
chmod +x /usr/local/bin/websocat

mkdir -p /home/user

cat << 'EOF' > /home/user/math_server.py
import asyncio
import websockets
import sys

async def evaluate(websocket, path):
    async for message in websocket:
        expr = message.strip()
        if "/" in expr:
            await websocket.send("MIGRATION_ERROR")
        else:
            try:
                ans = eval(expr)
                await websocket.send(str(ans))
            except:
                await websocket.send("ERR")

start_server = websockets.serve(evaluate, "127.0.0.1", 8888)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

cat << 'EOF' > /home/user/start_server.sh
#!/bin/bash
python2 /home/user/math_server.py &
EOF
chmod +x /home/user/start_server.sh

cat << 'EOF' > /home/user/expressions.txt
15 + 20
100 / 3
50 * 2
7 / 2
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
