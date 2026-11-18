#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest fastapi uvicorn pandas networkx requests redis

    mkdir -p /home/user/workspace
    mkdir -p /app

    # Create the FastAPI application
    cat << 'EOF' > /app/api.py
from fastapi import FastAPI
import random

app = FastAPI()

# Generate deterministic synthetic data
random.seed(42)
transactions = []
for i in range(5000):
    transactions.append({
        "tx_id": f"tx_{i}",
        "sender_id": f"U-{random.randint(1, 200):03d}",
        "receiver_id": f"U-{random.randint(1, 200):03d}",
        "amount": round(random.uniform(10, 1000), 2),
        "timestamp": "2023-01-01T00:00:00Z"
    })

@app.get("/transactions")
def get_transactions(page: int = 1):
    page_size = 100
    start = (page - 1) * page_size
    if start >= len(transactions):
        return []

    # Simulate overlapping rows bug
    if page > 1:
        start = max(0, start - 20)
    end = (page * page_size)

    return transactions[start:end]
EOF

    # Create dummy golden top 100 to satisfy verifier if needed
    cat << 'EOF' > /app/golden_top100.txt
U-001
U-002
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
