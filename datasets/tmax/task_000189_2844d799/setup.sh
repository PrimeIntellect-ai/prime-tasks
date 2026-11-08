#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak git
    pip3 install pytest fastapi uvicorn pydantic

    mkdir -p /app
    espeak -w /app/incident_voicemail.wav "The failing tenant ID is eight four seven two."

    mkdir -p /app/uptime_repo
    cd /app/uptime_repo
    git init

    cat << 'EOF' > server.py
from fastapi import FastAPI, Header, HTTPException
import asyncio
from pydantic import BaseModel

app = FastAPI()

API_KEY = "secr3t_m@th_88"

class Ping(BaseModel):
    uptime_ms: float

db = {}

def calculate_ema(new_value: float, current_ema: float, alpha: float = 0.1) -> float:
    # BUG: incorrect formula
    return alpha * new_value + alpha * current_ema

@app.post("/record_ping/{tenant_id}")
async def record_ping(tenant_id: str, ping: Ping, x_api_key: str = Header(None)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")

    current_ema = db.get(tenant_id, 0.0)
    await asyncio.sleep(0.01)

    new_ema = calculate_ema(ping.uptime_ms, current_ema)
    db[tenant_id] = new_ema
    return {"status": "ok"}

@app.get("/uptime/{tenant_id}")
async def get_uptime(tenant_id: str, x_api_key: str = Header(None)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return {"ema": db.get(tenant_id, 0.0)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=9090)
EOF

    git config --global user.email "sre@company.com"
    git config --global user.name "SRE"
    git add server.py
    git commit -m "Initial commit with API key"

    sed -i 's/API_KEY = "secr3t_m@th_88"/API_KEY = ""/' server.py
    git add server.py
    git commit -m "Remove API key for security"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
