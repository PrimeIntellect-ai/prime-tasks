#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl openssl
    pip3 install pytest Flask redis PyJWT

    mkdir -p /app/nginx/ssl /app/logs /app/flask /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/logs/api_access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 +0000] "GET /api/data" 200 - "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdCJ9.signature"
10.13.37.99 - - [10/Oct/2023:14:02:11 +0000] "GET /api/admin" 200 - "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
172.16.0.4 - - [10/Oct/2023:14:15:00 +0000] "GET /api/data" 401 - "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYm9iIn0.bad"
EOF

    cat << 'EOF' > /app/generate_corpora.py
import jwt, time, os

secret = "Secret-Responder-Key-99!"

# Clean
with open("/app/corpora/clean/valid_1.jwt", "w") as f:
    f.write(jwt.encode({"user": "alice", "exp": time.time() + 3600}, secret, algorithm="HS256"))

# Evil - none alg
with open("/app/corpora/evil/evil_none.jwt", "w") as f:
    f.write("eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWxpY2UiLCJleHAiOjE5OTk5OTk5OTl9.")

# Evil - expired
with open("/app/corpora/evil/evil_expired.jwt", "w") as f:
    f.write(jwt.encode({"user": "alice", "exp": time.time() - 3600}, secret, algorithm="HS256"))

# Evil - bad sig
with open("/app/corpora/evil/evil_bad_sig.jwt", "w") as f:
    f.write(jwt.encode({"user": "alice", "exp": time.time() + 3600}, "wrong_secret", algorithm="HS256"))
EOF

    python3 /app/generate_corpora.py

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /app/nginx/ssl/cert.pem;
        ssl_certificate_key /app/nginx/ssl/key.pem;

        location / {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /app/flask/app.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/health')
def health():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/flask/app.py > /app/logs/flask.log 2>&1 &
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
