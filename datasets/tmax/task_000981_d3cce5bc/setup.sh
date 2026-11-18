#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random
import os

db_path = "/home/user/ecommerce.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create tables
c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL)")
c.execute("CREATE TABLE referrals (referrer_id INTEGER, referred_id INTEGER)")

# Populate users
users = [(i, f"User_{i}") for i in range(1, 21)]
c.executemany("INSERT INTO users VALUES (?, ?)", users)

# Populate transactions
random.seed(42)
transactions = []
t_id = 1
for u_id in range(1, 21):
    for _ in range(random.randint(0, 3)):
        amount = round(random.uniform(10.0, 100.0), 2)
        transactions.append((t_id, u_id, amount))
        t_id += 1
c.executemany("INSERT INTO transactions VALUES (?, ?, ?)", transactions)

# Populate referrals (Directed graph)
referrals = [
    (1, 2), (1, 3),
    (2, 4), (2, 5),
    (3, 6),
    (4, 7), (5, 8),
    (8, 9),
    (10, 11)
]
c.executemany("INSERT INTO referrals VALUES (?, ?)", referrals)

conn.commit()
conn.close()

# Create buggy script
buggy_script = """import sqlite3
import json

def run_pipeline():
    conn = sqlite3.connect('/home/user/ecommerce.db')
    c = conn.cursor()

    # TODO: Filter target_users using graph traversal from referrals table (seed user_id = 1, max hops = 2)
    target_users = [1, 2, 3] # Hardcoded for now

    # BUGGY QUERY WITH CROSS JOIN AND UNSAFE FORMATTING
    user_ids_str = ",".join(map(str, target_users))
    query = f\"\"\"
    SELECT u.id, u.name, SUM(t.amount)
    FROM users u, transactions t
    WHERE u.id IN ({user_ids_str})
    GROUP BY u.id, u.name
    \"\"\"

    c.execute(query)
    results = c.fetchall()

    output = []
    for row in results:
        output.append({
            "user_id": row[0],
            "name": row[1],
            "total_spent": round(row[2], 2)
        })

    with open('/home/user/final_report.json', 'w') as f:
        json.dump(output, f, indent=4)

if __name__ == "__main__":
    run_pipeline()
"""
with open("/home/user/etl_pipeline.py", "w") as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
