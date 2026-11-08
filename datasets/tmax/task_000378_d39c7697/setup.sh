#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/tx_analyzer
cd /home/user/tx_analyzer

python3 -c "
import sqlite3
import random

conn = sqlite3.connect('transactions.db')
c = conn.cursor()
c.execute('''CREATE TABLE tx (id INTEGER PRIMARY KEY, user_id TEXT, amount REAL, type TEXT)''')

random.seed(42)
users = ['U10', 'U15', 'U20']
types = ['purchase', 'refund']

# Insert data ensuring U15 has a predictable sum
c.execute(\"INSERT INTO tx (user_id, amount, type) VALUES ('U15', 500.0, 'purchase')\")
c.execute(\"INSERT INTO tx (user_id, amount, type) VALUES ('U15', 150.0, 'refund')\")
c.execute(\"INSERT INTO tx (user_id, amount, type) VALUES ('U15', 200.0, 'purchase')\")
c.execute(\"INSERT INTO tx (user_id, amount, type) VALUES ('U15', 50.0, 'refund')\")
conn.commit()
conn.close()
"

git init
git config user.email "dev@example.com"
git config user.name "Dev"

cat << 'EOF' > analyzer.py
import sqlite3
import sys

def get_balance(user_id):
    conn = sqlite3.connect('transactions.db')
    c = conn.cursor()
    # CORRECT LOGIC
    c.execute("SELECT type, amount FROM tx WHERE user_id = ?", (user_id,))
    rows = c.fetchall()
    balance = 0.0
    for t, amount in rows:
        if t == 'refund':
            balance -= amount
        else:
            balance += amount
    conn.close()
    return balance

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python analyzer.py <user_id>")
        sys.exit(1)
    print(get_balance(sys.argv[1]))
EOF

git add analyzer.py transactions.db
git commit -m "Initial commit: basic analyzer setup"

# Add 8 good commits
for i in $(seq 1 8); do
    echo "# comment $i" >> analyzer.py
    git commit -am "Minor update $i"
done

# Introduce the bug in the 10th commit (Index 9 from 0)
cat << 'EOF' > analyzer.py
import sqlite3
import sys

def get_balance(user_id):
    conn = sqlite3.connect('transactions.db')
    c = conn.cursor()
    # BUGGY LOGIC: Ignoring refunds completely
    c.execute("SELECT type, amount FROM tx WHERE user_id = ? AND type != 'failed'", (user_id,))
    rows = c.fetchall()
    balance = 0.0
    for t, amount in rows:
        balance += amount # BUG: doesn't subtract refunds
    conn.close()
    return balance

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python analyzer.py <user_id>")
        sys.exit(1)
    print(get_balance(sys.argv[1]))
EOF
# Add the comments back to match line counts somewhat
for i in $(seq 1 8); do
    echo "# comment $i" >> analyzer.py
done

git commit -am "Optimize query for balance calculation"
BAD_COMMIT=$(git rev-parse HEAD)

# Add 10 more "bad" commits (unrelated changes)
for i in $(seq 9 18); do
    echo "# another comment $i" >> analyzer.py
    git commit -am "Unrelated change $i"
done

echo $BAD_COMMIT > /home/user/.secret_bad_commit

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
