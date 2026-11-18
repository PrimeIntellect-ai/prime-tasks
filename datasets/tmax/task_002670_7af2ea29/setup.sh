#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/research_data.sqlite')
c = conn.cursor()

# tbl_A: Authors (id, str_val)
c.execute('CREATE TABLE tbl_A (id INTEGER PRIMARY KEY, str_val TEXT)')
authors = [
    (1, 'Alice Smith'),
    (2, 'Bob Jones'),
    (3, 'Charlie Brown'),
    (4, 'Dave Davis')
]
c.executemany('INSERT INTO tbl_A VALUES (?,?)', authors)

# tbl_B: Papers (id, str_val, num_val)
c.execute('CREATE TABLE tbl_B (id INTEGER PRIMARY KEY, str_val TEXT, num_val INTEGER)')
papers = [
    (101, 'Deep Learning Basics', 2018),
    (102, 'Advanced Neural Nets', 2019),
    (103, 'Graph Databases', 2020),
    (104, 'Data Mining Approaches', 2021)
]
c.executemany('INSERT INTO tbl_B VALUES (?,?,?)', papers)

# tbl_C: Authorships (x_id, y_id) -> Author ID, Paper ID
c.execute('CREATE TABLE tbl_C (x_id INTEGER, y_id INTEGER)')
authorships = [
    (1, 101),
    (2, 102),
    (3, 103),
    (1, 103), # Alice is a co-author on paper 103
    (4, 104)
]
c.executemany('INSERT INTO tbl_C VALUES (?,?)', authorships)

# tbl_D: Citations (u_id, v_id) -> Source Paper ID, Target Paper ID
c.execute('CREATE TABLE tbl_D (u_id INTEGER, v_id INTEGER)')
citations = [
    (101, 102), # P101 (Alice) cites P102 (Bob)
    (101, 103), # P101 (Alice) cites P103 (Charlie, Alice). Alice->Alice filtered. Alice->Charlie counted.
    (104, 101), # P104 (Dave) cites P101 (Alice).
    (104, 103)  # P104 (Dave) cites P103 (Charlie, Alice).
]
c.executemany('INSERT INTO tbl_D VALUES (?,?)', citations)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
