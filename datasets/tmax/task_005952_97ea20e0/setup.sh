#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl ruby
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    pip3 install pytest websockets

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > package.json
{
  "name": "eval-server",
  "version": "1.0.0",
  "dependencies": {
    "ws": "^8.14.2"
  }
}
EOF

    npm install ws

    cat << 'EOF' > server.js
const WebSocket = require('ws');
const http = require('http');
const { exec } = require('child_process');

const server = http.createServer();
const wss = new WebSocket.Server({ noServer: true });

server.on('upgrade', function upgrade(request, socket, head) {
    // BUG: Poor routing, doesn't restrict languages properly
    const match = request.url.match(/\/eval\/(.+)/);
    if (!match) {
        socket.destroy();
        return;
    }
    const lang = match[1];

    wss.handleUpgrade(request, socket, head, function done(ws) {
        wss.emit('connection', ws, request, lang);
    });
});

wss.on('connection', function connection(ws, request, lang) {
    ws.on('message', function incoming(message) {
        try {
            const data = JSON.parse(message);
            const expr = data.expr;

            let cmd = '';
            // BUG: Evaluates as string output, doesn't handle JSON typing
            if (lang === 'python') cmd = `python3 -c "print(eval('${expr}'))"`;
            else if (lang === 'ruby') cmd = `ruby -e "puts eval('${expr}')"`;
            else if (lang === 'node') cmd = `node -e "console.log(eval('${expr}'))"`;

            exec(cmd, (err, stdout, stderr) => {
                if (err) {
                    ws.send(JSON.stringify({ error: err.message }));
                    return;
                }
                // BUG: stdout.trim() is always a string
                ws.send(JSON.stringify({ result: stdout.trim() }));
            });
        } catch (e) {
            ws.send(JSON.stringify({ error: "Invalid JSON" }));
        }
    });
});

server.listen(8080);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
