#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    pip3 install pytest flask requests

    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/data

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
cd /home/user/app/backend && python3 server.py &
cd /home/user/app/gateway && npm install && node index.js &
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /home/user/app/backend/server.py
from flask import Flask, request, jsonify
from parser import parse_log

app = Flask(__name__)

@app.route('/parse', methods=['POST'])
def parse():
    data = request.json
    results = []
    for line in data.get('logs', []):
        results.append(parse_log(line))
    return jsonify({"results": results})

if __name__ == '__main__':
    app.run(port=5001)
EOF

    cat << 'EOF' > /home/user/app/backend/parser.py
def parse_log(text):
    text = text.strip()
    # Infinite loop bug when there is a missing closing bracket
    while text.startswith('['):
        end_idx = text.rfind(']')
        if end_idx == -1:
            # Bug: missing break/return, causes infinite loop
            pass
        else:
            text = text[1:end_idx].strip()
    return text
EOF

    cat << 'EOF' > /home/user/app/gateway/index.js
const express = require('express');
const axios = require('axios');
const app = express();
app.use(express.json());

app.post('/process_logs', async (req, res) => {
    try {
        const response = await axios.post('http://localhost:5001/parse', req.body, { timeout: 2000 });
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Backend timeout or error' });
    }
});

app.listen(5000, () => console.log('Gateway listening on port 5000'));
EOF

    cat << 'EOF' > /home/user/app/gateway/package.json
{
  "name": "gateway",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.4.0"
  }
}
EOF

    python3 -c "
with open('/home/user/app/data/massive_log.txt', 'w') as f:
    for i in range(2500):
        f.write(f'[INFO] Server started at step {i}\n')
    f.write('[ERROR] [System] [Auth Missing closing bracket\n')
    for i in range(2501, 5000):
        f.write(f'[INFO] Server started at step {i}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
