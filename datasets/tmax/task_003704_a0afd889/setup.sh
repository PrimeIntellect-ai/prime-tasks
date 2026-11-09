#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git redis-server
    pip3 install pytest fastapi uvicorn redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/worker
    mkdir -p /home/user/app/frontend

    cd /home/user/app
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Create the initial worker config with the hardcoded secret
    cat << 'EOF' > worker/config.py
API_SECRET = "git-sec-9942x"
EOF
    git add worker/config.py
    git commit -m "Initial commit: add worker config"

    # Modify worker config to remove the secret
    cat << 'EOF' > worker/config.py
import os
API_SECRET = os.environ['API_SECRET']
EOF
    git add worker/config.py
    git commit -m "Security: remove hardcoded API_SECRET"

    # Create worker main script
    cat << 'EOF' > worker/main.py
import time
import redis
from config import API_SECRET

if API_SECRET != "git-sec-9942x":
    raise ValueError("Invalid API_SECRET")

r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)
while True:
    try:
        r.set("secret_data", "secret-payload-from-redis")
        time.sleep(10)
    except Exception as e:
        print("Worker redis connection failed:", e)
        time.sleep(2)
EOF

    # Create frontend main script
    cat << 'EOF' > frontend/main.py
import os
from fastapi import FastAPI, Header, HTTPException
import redis

INIT_TOKEN = os.environ.get("INIT_TOKEN")
if INIT_TOKEN != "TOKEN-A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6":
    raise RuntimeError("Missing or invalid INIT_TOKEN")

app = FastAPI()
r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/secure-data")
def secure_data(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    token = authorization.split(" ")[1]
    if token != "git-sec-9942x":
        raise HTTPException(status_code=403, detail="Forbidden")

    try:
        data = r.get("secret_data")
    except Exception:
        raise HTTPException(status_code=500, detail="Redis connection failed")

    if not data:
        raise HTTPException(status_code=500, detail="Data not ready")
    return {"data": data}
EOF

    # Create the crash dump file with the embedded token
    head -c 1024 /dev/urandom > frontend_crash.dump
    echo -n "TOKEN-A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6" >> frontend_crash.dump
    head -c 1024 /dev/urandom >> frontend_crash.dump

    # Create the buggy start script
    cat << 'EOF' > start.sh
#!/bin/bash
redis-server --port 6380 &
python3 worker/main.py &
uvicorn frontend.main:app --host 127.0.0.1 --port 8080 &
wait
EOF
    chmod +x start.sh

    # Commit the rest of the files
    git add worker/main.py frontend/main.py start.sh frontend_crash.dump
    git commit -m "Add remaining services and files"

    chmod -R 777 /home/user
