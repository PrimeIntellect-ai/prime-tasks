#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm curl
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy
    cd /home/user/legacy
    npm install ws

    cat << 'EOF' > /home/user/legacy/fetch_limits.js
const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:9999');

ws.on('open', function open() {
  console.log('Connected to build agent.');
});

ws.on('message', function incoming(data) {
  const expressions = JSON.parse(data);
  console.log('Received constraints:', expressions);

  // INSECURE EVALUATION
  const results = expressions.map(expr => eval(expr));

  ws.send(JSON.stringify(results));
  ws.close();
});
EOF

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import json

async def handler(websocket, path):
    # Send constraint expressions
    expressions = [
        "4 + 5",
        "10 * (2 + 3)",
        "100 / 4 - 5"
    ]
    expected_results = [9, 50, 20]

    await websocket.send(json.dumps(expressions))

    try:
        response = await websocket.recv()
        results = json.loads(response)

        if results == expected_results:
            with open("/home/user/result.txt", "w") as f:
                f.write("SUCCESS_84729_SECURE_EVAL")
    except Exception as e:
        print(f"Error: {e}")

start_server = websockets.serve(handler, "localhost", 9999)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    # Add server start to bashrc so it runs when the agent/user connects
    echo "python3 /home/user/ws_server.py > /tmp/ws_server.log 2>&1 &" >> /home/user/.bashrc
    echo "sleep 1" >> /home/user/.bashrc

    chown -R user:user /home/user
    chmod -R 777 /home/user
