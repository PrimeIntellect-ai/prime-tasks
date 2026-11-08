#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server cargo rustc curl
pip3 install pytest fastapi uvicorn pydantic redis

mkdir -p /app
cd /app

cat << 'EOF' > mock_api.py
from fastapi import FastAPI
from pydantic import BaseModel
import hashlib

app = FastAPI()

class Item(BaseModel):
    text: str

@app.post("/embed")
def embed(item: Item):
    h = hashlib.md5(item.text.encode()).digest()
    return {"embedding": list(h)}
EOF

cat << 'EOF' > start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app && uvicorn mock_api:app --host 127.0.0.1 --port 8000 &
sleep 2
EOF
chmod +x start_services.sh

cat << 'EOF' > oracle_processor
#!/usr/bin/env python3
import sys
import json
import re
import urllib.request
import redis

r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)

for line in sys.stdin:
    if not line.strip():
        continue
    data = json.loads(line)
    text = data.get("text", "")

    text = text.lower()
    text = re.sub(r'[^a-z0-9]', ' ', text)
    tokens = [t for t in text.split() if t][:10]
    normalized_text = " ".join(tokens)

    cache_key = f"embed:{normalized_text}"
    cached = r.get(cache_key)
    if cached:
        embedding = json.loads(cached)
    else:
        req_data = json.dumps({"text": normalized_text}).encode('utf-8')
        req = urllib.request.Request("http://127.0.0.1:8000/embed", data=req_data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req) as response:
                resp_data = json.loads(response.read().decode())
                embedding = resp_data["embedding"]
            r.set(cache_key, json.dumps(embedding))
        except Exception:
            embedding = []

    out = {
        "id": data["id"],
        "tokens": tokens,
        "embedding": embedding
    }
    print(json.dumps(out))
EOF
chmod +x oracle_processor

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
