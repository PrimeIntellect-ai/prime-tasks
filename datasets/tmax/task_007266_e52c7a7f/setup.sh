#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/scripts

    sqlite3 /home/user/data/prod_temp.db "CREATE TABLE secrets (id INTEGER PRIMARY KEY, secret_code TEXT);"
    sqlite3 /home/user/data/prod_temp.db "INSERT INTO secrets (secret_code) VALUES ('ALPHA-992'), ('BRAVO-713'), ('CHARLIE-404'), ('DELTA-505');"

    cat /home/user/data/prod_temp.db > /home/user/data/prod.db
    dd if=/dev/urandom of=/home/user/data/prod.db bs=1 count=16 conv=notrunc
    rm /home/user/data/prod_temp.db

    cat << 'EOF' > /home/user/scripts/extract_secrets.py
import sqlite3
import sys
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 extract_secrets.py <db_path>")
        sys.exit(1)

    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT id, secret_code FROM secrets ORDER BY id")
    records = cur.fetchall()

    out_path = '/home/user/recovery_output.txt'
    if os.path.exists(out_path):
        os.remove(out_path)

    # BUG: Off-by-one error causing IndexError
    for i in range(len(records) + 1):
        assert i >= 0, "Index must be non-negative"
        record = records[i]
        with open(out_path, 'a') as f:
            f.write(f"{record[0]}:{record[1]}\n")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/scripts/extract_secrets.py
    chmod -R 777 /home/user
