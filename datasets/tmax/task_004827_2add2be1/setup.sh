#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server openssl
pip3 install pytest flask redis pyjwt pandas

mkdir -p /app/auth_service /app/nginx /app/certs /app/logs
mkdir -p /home/user

# Generate certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /app/certs/server.key \
    -out /app/certs/server.crt \
    -subj "/C=US/ST=State/L=City/O=Org/CN=localhost"

# Create /app/auth_service/app.py
cat << 'EOF' > /app/auth_service/app.py
from flask import Flask, request, jsonify
import jwt
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)
SECRET_KEY = "super_secret_key"

@app.route('/verify', methods=['GET'])
def verify():
    token = request.headers.get('Authorization')
    if not token:
        return jsonify({"error": "Missing token"}), 401

    try:
        # VULNERABLE: verify_signature=False
        decoded = jwt.decode(token, options={"verify_signature": False})
        return jsonify({"status": "success", "user": decoded.get("user_id")})
    except Exception as e:
        return jsonify({"error": str(e)}), 401

if __name__ == '__main__':
    # VULNERABLE: binds to 0.0.0.0
    app.run(host='0.0.0.0', port=5000)
EOF

# Create /app/nginx/nginx.conf
cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 80;
        server_name localhost;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

# Create /app/start.sh
cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
python3 /app/auth_service/app.py &
wait
EOF
chmod +x /app/start.sh

# Generate logs and ground truth
cat << 'EOF' > /tmp/gen_logs.py
import json
import random
import time
import jwt
import csv

SECRET_KEY = "super_secret_key"
logs = []
compromised = []

for i in range(100):
    user_id = f"user_{random.randint(100, 999)}"
    timestamp = int(time.time()) - random.randint(1000, 100000)
    ip = f"192.168.1.{random.randint(1, 254)}"

    is_compromised = random.choice([True, False])
    if is_compromised:
        payload = {"user_id": user_id, "exp": timestamp + 3600}
        header = {"alg": "none", "typ": "JWT"}
        header_b64 = jwt.utils.base64url_encode(json.dumps(header).encode()).decode()
        payload_b64 = jwt.utils.base64url_encode(json.dumps(payload).encode()).decode()
        token = f"{header_b64}.{payload_b64}."
        compromised.append({"user_id": user_id, "timestamp": timestamp})
    else:
        payload = {"user_id": user_id, "exp": timestamp + 3600}
        token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")

    logs.append({"timestamp": timestamp, "ip": ip, "token": token})

with open('/app/logs/auth.log', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")

with open('/root/ground_truth_compromised.csv', 'w') as f:
    writer = csv.DictWriter(f, fieldnames=["user_id", "timestamp"])
    writer.writeheader()
    for row in compromised:
        writer.writerow(row)
EOF
python3 /tmp/gen_logs.py

useradd -m -s /bin/bash user || true
chown -R user:user /app
chmod -R 777 /home/user
