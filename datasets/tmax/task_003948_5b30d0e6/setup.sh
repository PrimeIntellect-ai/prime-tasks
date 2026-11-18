#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /home/user/proxy /home/user/backend /app

    cat << 'EOF' > /home/user/proxy/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        server_name localhost;

        # AGENT MUST ADD LOCATION BLOCK HERE
    }
}
EOF

    cat << 'EOF' > /home/user/backend/app.py
import os
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/inspect', methods=['GET'])
def inspect():
    key = os.environ.get('AUTH_KEY')
    if key != 'AlphaBravo123':
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"status": "success", "token": "TkVUOlhYW"}), 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/legacy_parser_src.py
import sys
import base64
import binascii

def main():
    if len(sys.argv) != 2:
        sys.exit(3)

    token = sys.argv[1]

    try:
        decoded = base64.b64decode(token, validate=True)
    except Exception:
        print("ERROR: INVALID_B64")
        sys.exit(1)

    if not decoded.startswith(b'NET:'):
        print("ERROR: BAD_HEADER")
        sys.exit(2)

    payload = decoded[4:]
    decrypted = bytes([b ^ 0x5C for b in payload])
    print(binascii.hexlify(decrypted).decode('ascii'))
    sys.exit(0)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /app/legacy_parser
#!/bin/bash
python3 /app/legacy_parser_src.py "$1"
EOF
    chmod +x /app/legacy_parser

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
