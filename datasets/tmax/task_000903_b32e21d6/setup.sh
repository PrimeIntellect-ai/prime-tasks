#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make curl
    pip3 install pytest

    mkdir -p /app/wal-config-server
    mkdir -p /app/data

    cat << 'EOF' > /app/wal-config-server/requirements.txt
fastapi
uvicorn
EOF

    cat << 'EOF' > /app/wal-config-server/Makefile
.PHONY: install run

install:
	pip3 install requirements.txt

run:
	uvicorn wal_server:app --host 127.0.0.1 --port 9090
EOF

    cat << 'EOF' > /app/wal-config-server/wal_server.py
from fastapi import FastAPI, Request
# Missing imports

app = FastAPI()

@app.post("/append")
async def append(request: Request):
    # TODO: Implement append logic
    # Requirement: The incoming payload is encoded in CP1252.
    # Convert to UTF-8 and append to /app/data/config.wal
    return {"status": "ok"}

@app.post("/commit")
async def commit():
    # TODO: Implement commit logic
    return {"status": "ok"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
