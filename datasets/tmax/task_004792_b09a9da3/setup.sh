#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest fastapi uvicorn hypothesis requests httpx

    mkdir -p /home/user/pr_review/logs
    cd /home/user/pr_review

    cat << 'EOF' > resolver.py
class ConstraintResolver:
    def __init__(self):
        self.items = []

    def add_item(self, value: int):
        self.items.append(value)

    def resolve(self, limit: int) -> list:
        # BUG: Fails when limit is 0
        ratio = sum(self.items) // limit 
        return [i for i in self.items if i <= limit]
EOF

    cat << 'EOF' > api.py
from fastapi import FastAPI, Header, HTTPException
from typing import Optional
from resolver import ConstraintResolver

app = FastAPI()

@app.get("/resolve")
def resolve_constraints(Constraint_Limit: Optional[int] = Header(None)):
    if Constraint_Limit is None:
        raise HTTPException(status_code=400, detail="Missing Constraint_Limit header")

    resolver = ConstraintResolver()
    resolver.add_item(5)
    resolver.add_item(10)

    try:
        result = resolver.resolve(Constraint_Limit)
        return {"result": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
EOF

    cat << 'EOF' > nginx.conf
events {
    worker_connections 1024;
}

http {
    access_log /home/user/pr_review/logs/access.log;
    error_log /home/user/pr_review/logs/error.log;

    # underscores_in_headers on; # MISSING THIS LINE

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:8000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    cat << 'EOF' > test_api.py
import pytest
import requests
from hypothesis import given, settings
from hypothesis.strategies import integers

@settings(max_examples=50, deadline=None)
@given(limit=integers(min_value=0, max_value=100))
def test_resolve_endpoint(limit):
    headers = {"Constraint_Limit": str(limit)}
    response = requests.get("http://localhost:8080/resolve", headers=headers)
    assert response.status_code == 200, f"Failed with limit {limit}, response: {response.text}"
    assert "result" in response.json()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
