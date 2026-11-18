#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > transactions.ttl
@prefix ex: <http://example.org/account/> .

ex:Acc1 ex:transfersTo ex:Acc2 .
ex:Acc2 ex:transfersTo ex:Acc3 .
ex:Acc3 ex:transfersTo ex:Acc1 .

ex:Acc4 ex:transfersTo ex:Acc5 .
ex:Acc5 ex:transfersTo ex:Acc6 .
ex:Acc6 ex:transfersTo ex:Acc7 .

ex:Acc8 ex:transfersTo ex:Acc9 .
ex:Acc9 ex:transfersTo ex:Acc10 .
ex:Acc10 ex:transfersTo ex:Acc8 .
EOF

    sqlite3 audit.db "CREATE TABLE accounts (id INTEGER PRIMARY KEY, status TEXT);"
    sqlite3 audit.db "INSERT INTO accounts (id, status) VALUES (1, 'pending'), (2, 'pending');"

    cat << 'EOF' > worker1.py
import sqlite3
import time

conn = sqlite3.connect('/home/user/audit.db', timeout=10)
try:
    conn.execute('BEGIN')
    conn.execute('SELECT * FROM accounts WHERE id=1')
    time.sleep(2)
    conn.execute('UPDATE accounts SET status="auditing" WHERE id=1')
    conn.commit()
except Exception as e:
    print("Worker 1 failed:", e)
finally:
    conn.close()
EOF

    cat << 'EOF' > worker2.py
import sqlite3
import time

conn = sqlite3.connect('/home/user/audit.db', timeout=10)
try:
    conn.execute('BEGIN')
    conn.execute('SELECT * FROM accounts WHERE id=2')
    time.sleep(2)
    conn.execute('UPDATE accounts SET status="auditing" WHERE id=2')
    conn.commit()
except Exception as e:
    print("Worker 2 failed:", e)
finally:
    conn.close()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
