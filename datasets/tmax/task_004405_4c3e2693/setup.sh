#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
conn = sqlite3.connect('/home/user/company.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
c.execute('CREATE TABLE messages (msg_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER)')
c.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'David', 2),
    (5, 'Eve', 2),
    (6, 'Frank', 3),
    (7, 'Grace', 3)
])
c.executemany('INSERT INTO messages (sender_id, receiver_id) VALUES (?, ?)', [
    (1, 2), (2, 1), (1, 3), (3, 1),
    (2, 4), (4, 2), (2, 5), (5, 2),
    (3, 6), (6, 3), (3, 7), (7, 3),
    (4, 5), (6, 7), (5, 6)
])
conn.commit()
conn.close()
"

    chmod -R 777 /home/user
