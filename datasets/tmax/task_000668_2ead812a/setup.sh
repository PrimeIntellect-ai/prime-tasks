#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl socat netcat-openbsd jq
    pip3 install pytest flask

    mkdir -p /app

    cat << 'EOF' > /app/aligner.py
from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route('/align', methods=['POST'])
def align():
    seq = request.data.decode('utf-8')
    return jsonify({"score": len(seq) * 2})
if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/fft.py
from flask import Flask, request, jsonify
app = Flask(__name__)
@app.route('/spectrum', methods=['POST'])
def spectrum():
    seq = request.data.decode('utf-8')
    if len(set(seq)) == 1:
        return "Internal Server Error", 500
    return jsonify({"dominant_freq": 0.33})
if __name__ == '__main__':
    app.run(port=5001)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
