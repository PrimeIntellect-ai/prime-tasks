#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/corp_data.db')
c = conn.cursor()

c.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT)''')
c.execute('''CREATE TABLE communications (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp TEXT, sensitivity_level INTEGER)''')

employees = [
    (1, 'Alice', 'HR'),
    (2, 'Bob', 'Engineering'),
    (3, 'Charlie', 'Engineering'),
    (4, 'Dave', 'Finance'),
    (5, 'Eve', 'Executive'),
    (6, 'Frank', 'Sales')
]
c.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

comms = [
    (1, 1, 2, '2022-12-31 23:59:59', 5),
    (2, 1, 2, '2023-05-01 10:00:00', 2),
    (3, 5, 2, '2023-06-01 10:00:00', 5),
    (4, 1, 2, '2023-06-02 10:00:00', 3),
    (5, 3, 2, '2023-06-03 10:00:00', 4),
    (6, 2, 4, '2023-06-04 10:00:00', 4),
    (7, 2, 3, '2023-06-05 10:00:00', 3),
    (8, 2, 6, '2023-06-06 10:00:00', 5),
    (9, 3, 4, '2023-06-07 10:00:00', 4),
]
c.executemany("INSERT INTO communications VALUES (?, ?, ?, ?, ?)", comms)

conn.commit()
conn.close()
EOF
python3 /tmp/setup_db.py
chown user:user /home/user/corp_data.db

chmod -R 777 /home/user
