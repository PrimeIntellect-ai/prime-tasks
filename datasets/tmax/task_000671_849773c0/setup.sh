#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

# 1. Setup Git repo and secret
mkdir -p /home/user/malware_repo
cd /home/user/malware_repo
git init
git config user.name "Malware Author"
git config user.email "author@malware.local"

cat << 'EOF' > key_gen.py
# Chaotic Key Generator
# Placeholder salt
SALT = "REPLACEME"

def generate_key():
    # Uses a logistic map: x_{n+1} = r * x_n * (1 - x_n)
    # x_0 is derived from the length of the salt
    # Initial value x_0 = len(SALT) / 100.0
    # r = 3.99

    x = len(SALT) / 100.0
    r = 3.99

    for _ in range(100):
        x = r * x * (1 - x)

    return x

if __name__ == "__main__":
    print(generate_key())
EOF

git add key_gen.py
git commit -m "Initial commit of key generator"

# Introduce the real salt
sed -i 's/SALT = "REPLACEME"/SALT = "sUp3r_s3cr3t_s4lt_99!"/' key_gen.py
git commit -am "Added secret salt"

# Remove the salt
sed -i 's/SALT = "sUp3r_s3cr3t_s4lt_99!"/SALT = "REPLACEME"/' key_gen.py
git commit -am "Oops, removed hardcoded secret"


# 2. Setup SQLite DB and WAL
mkdir -p /home/user/target_data
cd /home/user/target_data

cat << 'EOF' > setup_db.py
import sqlite3
import os

# Enable WAL mode
conn = sqlite3.connect("targets.db")
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE targets (id INTEGER PRIMARY KEY, email TEXT)")
conn.execute("INSERT INTO targets (email) VALUES ('ceo@megacorp.local')")
conn.commit()

# Start a transaction and exit forcefully to leave the WAL file intact
conn.execute("BEGIN EXCLUSIVE")
conn.execute("INSERT INTO targets (email) VALUES ('dummy@megacorp.local')")
os._exit(0)
EOF

python3 setup_db.py
rm setup_db.py

# Wipe the main database but leave the WAL
dd if=/dev/zero of=targets.db bs=1M count=1 2>/dev/null || true

# Ensure WAL is there and readable
chmod 644 targets.db-wal targets.db

chmod -R 777 /home/user
