#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3

def setup():
    conn = sqlite3.connect('/home/user/audit.db')
    c = conn.cursor()
    c.execute('''
        CREATE TABLE db_locks (
            id INTEGER PRIMARY KEY,
            pid INTEGER,
            resource TEXT,
            status TEXT,
            req_time DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    data = [
        (101, 'Res_A', 'GRANTED'),
        (102, 'Res_B', 'GRANTED'),
        (103, 'Res_C', 'GRANTED'),
        (101, 'Res_B', 'WAITING'),
        (102, 'Res_C', 'WAITING'),
        (103, 'Res_A', 'WAITING'),
        (104, 'Res_A', 'WAITING'),
        (105, 'Res_B', 'WAITING'),
        (106, 'Res_D', 'GRANTED'),
        (106, 'Res_E', 'GRANTED'),
        (106, 'Res_F', 'GRANTED'),
        (106, 'Res_G', 'GRANTED'),
        (107, 'Res_H', 'GRANTED'),
        (107, 'Res_H', 'WAITING')
    ]

    c.executemany('INSERT INTO db_locks (pid, resource, status) VALUES (?, ?, ?)', data)
    conn.commit()
    conn.close()

if __name__ == '__main__':
    setup()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
