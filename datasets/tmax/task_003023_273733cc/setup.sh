#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

def setup_db():
    conn = sqlite3.connect('/home/user/infra_graph.db')
    c = conn.cursor()

    c.execute('CREATE TABLE Nodes (id TEXT PRIMARY KEY, label TEXT, name TEXT)')
    c.execute('CREATE TABLE Edges (source TEXT, target TEXT, type TEXT)')

    nodes = [
        ('GatewayAPI', 'Service', 'GatewayAPI'),
        ('AuthService', 'Service', 'AuthService'),
        ('BillingService', 'Service', 'BillingService'),
        ('PaymentProcessor', 'Service', 'PaymentProcessor'),
        ('InventoryService', 'Service', 'InventoryService'),
        ('db-auth', 'Database', 'db-auth'),
        ('db-billing', 'Database', 'db-billing'),
        ('srv-core-01', 'Server', 'srv-core-01'),
        ('srv-replica-01', 'Server', 'srv-replica-01')
    ]

    edges = [
        ('GatewayAPI', 'AuthService', 'DEPENDS_ON'),
        ('GatewayAPI', 'BillingService', 'DEPENDS_ON'),
        ('GatewayAPI', 'InventoryService', 'DEPENDS_ON'),
        ('AuthService', 'db-auth', 'DEPENDS_ON'),
        ('BillingService', 'PaymentProcessor', 'DEPENDS_ON'),
        ('BillingService', 'db-billing', 'DEPENDS_ON'),
        ('db-auth', 'srv-core-01', 'HOSTED_ON'),
        ('db-billing', 'srv-core-01', 'HOSTED_ON'),
        ('PaymentProcessor', 'srv-replica-01', 'HOSTED_ON')
    ]

    c.executemany('INSERT INTO Nodes VALUES (?,?,?)', nodes)
    c.executemany('INSERT INTO Edges VALUES (?,?,?)', edges)

    conn.commit()
    conn.close()

if __name__ == '__main__':
    setup_db()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
