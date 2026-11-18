#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest fastapi uvicorn capstone pydantic httpx

    mkdir -p /home/user/app/nginx \
             /home/user/app/api \
             /home/user/app/corpora/evil \
             /home/user/app/corpora/clean

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        # TODO: Add location block to proxy /api/ to http://127.0.0.1:5000
    }
}
EOF

    cat << 'EOF' > /home/user/app/api/main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

class ExecRequest(BaseModel):
    hex_code: str

@app.post("/api/execute")
def execute_code(req: ExecRequest):
    # TODO: Implement capstone disassembly and filtering here
    # Disassemble the x86_64 hex string.
    # If it contains 'syscall', 'int', 'int3', or 'sysenter', raise HTTP 403:
    # raise HTTPException(status_code=403, detail="Malicious code detected")

    return {"status": "safe"}
EOF

    # Populate evil corpus
    echo '{"hex_code": "0f05"}' > /home/user/app/corpora/evil/1.json
    echo '{"hex_code": "909090cd80"}' > /home/user/app/corpora/evil/2.json
    echo '{"hex_code": "cc"}' > /home/user/app/corpora/evil/3.json
    echo '{"hex_code": "0f34"}' > /home/user/app/corpora/evil/4.json

    # Populate clean corpus
    echo '{"hex_code": "4831c0"}' > /home/user/app/corpora/clean/1.json
    echo '{"hex_code": "4883c408"}' > /home/user/app/corpora/clean/2.json
    echo '{"hex_code": "90909090"}' > /home/user/app/corpora/clean/3.json
    echo '{"hex_code": "4889e5"}' > /home/user/app/corpora/clean/4.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
