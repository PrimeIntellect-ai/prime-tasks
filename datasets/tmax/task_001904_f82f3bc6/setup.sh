#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask requests python-dotenv

    mkdir -p /app/frontend /app/crypto_service /app/system_audit /app/logs /app/data

    cat << 'EOF' > /app/frontend/app.py
from flask import Flask, request, jsonify
import requests
import os
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/read')
def read_file():
    filename = request.args.get('file')
    with open(f"/app/data/{filename}", "r") as f:
        return f.read()

@app.route('/encrypt', methods=['POST'])
def encrypt():
    text = request.form.get('text')
    crypto_url = os.getenv('CRYPTO_SERVICE_URL', 'http://127.0.0.1:9999')
    resp = requests.post(f"{crypto_url}/encrypt", data={"text": text})
    return resp.text

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /app/frontend/.env
CRYPTO_SERVICE_URL=http://127.0.0.1:9999
REDIS_URL=redis://127.0.0.1:6379
EOF

    cat << 'EOF' > /app/crypto_service/cipher.py
from flask import Flask, request
import os

app = Flask(__name__)

KEY = b"UEUQ"

def xor_crypt(data: bytes) -> bytes:
    return bytes([data[i] ^ KEY[i % len(KEY)] for i in range(len(data))])

@app.route('/encrypt', methods=['POST'])
def encrypt():
    text = request.form.get('text').encode()
    return xor_crypt(text).hex()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    python3 -c '
key = b"UEUQ"
flag = b"FLAG{x0r_1s_n0t_s3cur3_3ncrypt10n}"
enc = bytes([flag[i] ^ key[i % len(key)] for i in range(len(flag))])
with open("/app/crypto_service/secret.enc", "wb") as f:
    f.write(enc)
'

    cat << 'EOF' > /app/crypto_service/test_vectors.txt
Plaintext: TEST
Ciphertext: 01001615
EOF

    cat << 'EOF' > /app/system_audit/backup.sh
#!/bin/bash
cd /app/logs
tar -cf /app/backup.tar *
EOF
    chmod +x /app/system_audit/backup.sh

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/crypto_service && python3 cipher.py &
cd /app/frontend && python3 app.py &
wait
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
