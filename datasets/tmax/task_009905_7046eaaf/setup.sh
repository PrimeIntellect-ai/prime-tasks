#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create the SQLite database setup script
    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('transactions.db')
c = conn.cursor()

c.execute('''CREATE TABLE accounts (id INTEGER PRIMARY KEY, status TEXT)''')
c.execute('''CREATE TABLE transactions (account_id INTEGER, amount REAL)''')

# Insert accounts
accounts = [
    (1, 'active'),
    (2, 'suspended'),
    (3, 'active'),
    (4, 'closed')
]
c.executemany('INSERT INTO accounts VALUES (?, ?)', accounts)

# Insert transactions
transactions = [
    # Normal account (Account 1)
    (1, 10.0), (1, 12.0), (1, 14.0),

    # Suspended account (Account 2)
    (2, 50.0), (2, 55.0), (2, 60.0),

    # High balance account causing catastrophic cancellation in naive variance (Account 3)
    # Using 1e10 base to force floating point precision issues
    (3, 10000000000.01), (3, 10000000000.02), (3, 10000000000.01), (3, 10000000000.03),

    # Closed account (Account 4)
    (4, 5.0), (4, 10.0)
]
c.executemany('INSERT INTO transactions VALUES (?, ?)', transactions)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    # Create the flawed Python script
    cat << 'EOF' > fraud_check.py
import sqlite3
import math

def get_accounts(conn):
    # BUG 1: Missing suspended accounts
    return conn.execute("SELECT id FROM accounts WHERE status = 'active'").fetchall()

def get_transactions(conn, account_id):
    return [row[0] for row in conn.execute("SELECT amount FROM transactions WHERE account_id = ?", (account_id,))]

def calc_std_dev(data):
    # BUG 2: Naive variance calculation causing numerical instability
    n = len(data)
    if n < 2: return 0.0
    sum_x = sum(data)
    sum_sq = sum(x**2 for x in data)

    # Catastrophic cancellation happens here for large values with small variances
    variance = (sum_sq - (sum_x**2) / n) / (n - 1)

    return math.sqrt(variance)

def main():
    conn = sqlite3.connect('/home/user/transactions.db')
    accounts = get_accounts(conn)

    with open('/home/user/flagged_accounts.txt', 'w') as f:
        for (acc_id,) in accounts:
            txs = get_transactions(conn, acc_id)
            if txs and len(txs) > 1:
                sd = calc_std_dev(txs)
                f.write(f"{acc_id},{sd:.4f}\n")

if __name__ == '__main__':
    main()
EOF

    chmod +x fraud_check.py
    chmod -R 777 /home/user
