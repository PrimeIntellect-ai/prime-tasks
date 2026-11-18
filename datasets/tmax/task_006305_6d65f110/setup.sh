#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import time

conn = sqlite3.connect('/home/user/finance.db')
c = conn.cursor()

c.execute('''
    CREATE TABLE tx_records (
        id INTEGER PRIMARY KEY,
        account_id INTEGER,
        tx_type TEXT,
        amount REAL,
        status TEXT
    )
''')

c.execute('''
    CREATE TABLE system_events (
        event_id INTEGER PRIMARY KEY,
        account_id INTEGER,
        event_code TEXT,
        event_timestamp INTEGER
    )
''')

# Insert data
# Account 101: Suspicious (2 deadlocks within 3600s). Credits: 5000, 2000. Debits: 1500. Net: 5500.00
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (101, 'ERR_DEADLOCK', 1600000000)")
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (101, 'ERR_DEADLOCK', 1600003000)") # 3000s difference
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (101, 'CREDIT', 5000.00, 'COMPLETED')")
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (101, 'CREDIT', 2000.00, 'COMPLETED')")
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (101, 'DEBIT', 1500.00, 'COMPLETED')")
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (101, 'CREDIT', 9999.99, 'ROLLED_BACK')")

# Account 102: Not suspicious (2 deadlocks but 4000s apart)
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (102, 'ERR_DEADLOCK', 1600000000)")
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (102, 'ERR_DEADLOCK', 1600004000)") # 4000s difference
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (102, 'CREDIT', 1000.00, 'COMPLETED')")

# Account 103: Suspicious (3 deadlocks within 1000s). Credits: 100.25. Debits: 50.00. Net: 50.25
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (103, 'ERR_DEADLOCK', 1600100000)")
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (103, 'ERR_DEADLOCK', 1600100500)")
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (103, 'ERR_DEADLOCK', 1600100900)")
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (103, 'CREDIT', 100.25, 'COMPLETED')")
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (103, 'DEBIT', 50.00, 'COMPLETED')")

# Account 104: Suspicious (2 deadlocks exactly 3600s apart). Net: -250.50
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (104, 'ERR_DEADLOCK', 1600200000)")
c.execute("INSERT INTO system_events (account_id, event_code, event_timestamp) VALUES (104, 'ERR_DEADLOCK', 1600203600)") # Exactly 3600
c.execute("INSERT INTO tx_records (account_id, tx_type, amount, status) VALUES (104, 'DEBIT', 250.50, 'COMPLETED')")

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    chmod 644 /home/user/finance.db

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
