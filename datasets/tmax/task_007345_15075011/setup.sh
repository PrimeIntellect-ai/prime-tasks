#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest networkx

useradd -m -s /bin/bash user || true

mkdir -p /home/user/etl

python3 -c "
import sqlite3
import os

os.makedirs('/home/user/etl', exist_ok=True)
conn = sqlite3.connect('/home/user/etl/source.db')
c = conn.cursor()

# Departments
c.execute('CREATE TABLE t_alpha (uid INTEGER PRIMARY KEY, moniker TEXT)')
c.executemany('INSERT INTO t_alpha VALUES (?, ?)', [
    (1, 'Sales'),
    (2, 'Engineering'),
    (3, 'HR'),
    (4, 'Legal')
])

# Employees
c.execute('CREATE TABLE t_beta (eid INTEGER PRIMARY KEY, ename TEXT, alpha_id INTEGER)')
c.executemany('INSERT INTO t_beta VALUES (?, ?, ?)', [
    (101, 'Alice', 2),
    (102, 'Bob', 2),
    (103, 'Charlie', 2),
    (104, 'Diana', 1),
    (105, 'Eve', 1),
    (106, 'Frank', 3),
    (107, 'Grace', 3),
    (108, 'Hank', 4)
])

# Messages
c.execute('CREATE TABLE t_gamma (mid INTEGER PRIMARY KEY, s_id INTEGER, r_id INTEGER)')
c.executemany('INSERT INTO t_gamma VALUES (?, ?, ?)', [
    (1, 102, 101),
    (2, 103, 101),
    (3, 104, 101),
    (4, 105, 101),
    (5, 101, 102),
    (6, 103, 102),
    (7, 101, 104),
    (8, 105, 104),
    (9, 104, 105),
    (10, 106, 107),
    (11, 107, 106),
    (12, 108, 101),
    (13, 102, 101)
])

conn.commit()
conn.close()
"

chmod -R 777 /home/user
