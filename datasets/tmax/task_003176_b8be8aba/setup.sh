#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests networkx fastapi uvicorn

    mkdir -p /app/legacy_system

    cat << 'EOF' > /app/legacy_system/server.py
from flask import Flask, jsonify
app = Flask(__name__)

# Data model: 
# Entities own accounts (owner_id in accounts -> entity_id)
# Transactions move money between accounts (from_acc, to_acc)

entities = [
    {"entity_id": "E1", "name": "Alice"},
    {"entity_id": "E2", "name": "Bob"},
    {"entity_id": "E3", "name": "Charlie"},
    {"entity_id": "E4", "name": "Diana"}
]

accounts = [
    {"account_id": "A1", "owner_id": "E1"},
    {"account_id": "A2", "owner_id": "E1"},
    {"account_id": "A3", "owner_id": "E2"},
    {"account_id": "A4", "owner_id": "E3"},
    {"account_id": "A5", "owner_id": "E4"}
]

transactions = [
    {"tx_id": "T1", "from_acc": "A1", "to_acc": "A3", "amount": 100},
    {"tx_id": "T2", "from_acc": "A3", "to_acc": "A4", "amount": 50},
    {"tx_id": "T3", "from_acc": "A2", "to_acc": "A5", "amount": 200},
    {"tx_id": "T4", "from_acc": "A5", "to_acc": "A1", "amount": 25},
    {"tx_id": "T5", "from_acc": "A3", "to_acc": "A1", "amount": 10}
]

@app.route('/api/entities')
def get_entities(): return jsonify(entities)

@app.route('/api/accounts')
def get_accounts(): return jsonify(accounts)

@app.route('/api/transactions')
def get_tx(): return jsonify(transactions)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
