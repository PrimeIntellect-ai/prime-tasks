#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3

conn = sqlite3.connect('/home/user/citations.db')
c = conn.cursor()
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)')
c.execute('CREATE TABLE citations (source_id INTEGER, target_id INTEGER, citation_date TEXT)')

papers = [
    (1, 'Paper A', 2015),
    (2, 'Paper B', 2016),
    (3, 'Paper C', 2018),
    (4, 'Paper D', 2021),
    (5, 'Paper E', 2017)
]
c.executemany('INSERT INTO papers VALUES (?, ?, ?)', papers)

citations = [
    (2, 1, '2016-01-01'),
    (2, 1, '2016-05-05'),
    (3, 1, '2018-02-02'),
    (3, 2, '2018-03-03'),
    (3, 2, '2018-01-01'),
    (4, 1, '2021-01-01'),
    (3, 4, '2021-02-02')
]
c.executemany('INSERT INTO citations VALUES (?, ?, ?)', citations)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
