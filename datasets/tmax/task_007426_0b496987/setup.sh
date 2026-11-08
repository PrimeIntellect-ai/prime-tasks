#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/analytics

    cat << 'EOF' > /home/user/analytics/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/analytics/portfolio.db')
c = conn.cursor()

c.execute('''CREATE TABLE trades (id INTEGER PRIMARY KEY, amount REAL, cashflow REAL)''')
c.execute('''CREATE TABLE trade_events (trade_id INTEGER, status TEXT)''')

# Insert 1000 trades. Large base amount, tiny cashflows.
for i in range(1, 1001):
    amount = 1000000.0 + (i * 0.0001)
    cashflow = 50000.0 + (i * 0.01)
    c.execute("INSERT INTO trades (id, amount, cashflow) VALUES (?, ?, ?)", (i, amount, cashflow))

    # Insert multiple events to create the join bug
    c.execute("INSERT INTO trade_events (trade_id, status) VALUES (?, ?)", (i, 'PENDING'))
    c.execute("INSERT INTO trade_events (trade_id, status) VALUES (?, ?)", (i, 'SETTLED'))

conn.commit()
conn.close()
EOF
    python3 /home/user/analytics/setup_db.py

    cat << 'EOF' > /home/user/analytics/engine.py
import sqlite3
import math

class ConvergenceError(Exception):
    pass

def fetch_trades():
    conn = sqlite3.connect('/home/user/analytics/portfolio.db')
    c = conn.cursor()
    # BUG 1: Missing filter for status = 'SETTLED', causes duplicate rows
    c.execute('''
        SELECT t.id, t.amount, t.cashflow 
        FROM trades t
        JOIN trade_events e ON t.id = e.trade_id
    ''')
    rows = c.fetchall()
    conn.close()
    return rows

def calculate_total_value(trades):
    total = 0.0
    # BUG 2: Standard float addition loses precision with large differences in magnitude
    # Expected fix: return math.fsum([t[1] for t in trades])
    for t in trades:
        total += t[1]
    return total

def calculate_yield(price, cashflow):
    # Newton-Raphson to find yield
    rate = 0.05
    for _ in range(100):
        # Simplified NPV calculation for a perpetuity for demonstration
        npv = (cashflow / rate) - price
        derivative = -cashflow / (rate ** 2)

        diff = npv / derivative
        rate -= diff

        # BUG 3: Exact float comparison never hits
        # Expected fix: if abs(diff) < 1e-7:
        if diff == 0.0: 
            return rate

    raise ConvergenceError(f"Did not converge. Last rate: {rate}")
EOF

    cat << 'EOF' > /home/user/analytics/run_job.py
from engine import fetch_trades, calculate_total_value, calculate_yield

def main():
    trades = fetch_trades()
    total_val = calculate_total_value(trades)

    total_cashflow = sum(t[2] for t in trades)

    try:
        avg_yield = calculate_yield(total_val, total_cashflow)
        with open('/home/user/analytics/result.txt', 'w') as f:
            f.write(f"{avg_yield:.8f}\n")
        print("Job completed successfully.")
    except Exception as e:
        print(f"Job failed: {e}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
