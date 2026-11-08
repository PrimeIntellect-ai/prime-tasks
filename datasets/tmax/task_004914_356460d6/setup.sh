#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    pip3 install pytest requests flask

    # Create directories
    mkdir -p /app/fixture
    mkdir -p /app/legacy
    mkdir -p /home/user/workspace

    # Create start_services.sh
    cat << 'EOF' > /app/fixture/start_services.sh
#!/bin/bash
node /app/fixture/producer.js &
python3 /app/fixture/cache.py &
echo "Services started."
EOF
    chmod +x /app/fixture/start_services.sh

    # Create dummy producer.js
    cat << 'EOF' > /app/fixture/producer.js
const http = require('http');
const server = http.createServer((req, res) => {
  if (req.url === '/telemetry') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: "123", raw_payload: "0000", ecc_block: "00" }));
  } else {
    res.writeHead(404);
    res.end();
  }
});
server.listen(8081, () => console.log('Producer running on 8081'));
EOF

    # Create dummy cache.py
    cat << 'EOF' > /app/fixture/cache.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/verify')
def verify():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(port=8083)
EOF

    # Create legacy ecc.js
    cat << 'EOF' > /app/legacy/ecc.js
// Custom ECC logic to be translated to Python
function decode(raw_payload, ecc_block) {
    // legacy logic
    return raw_payload;
}
module.exports = { decode };
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
