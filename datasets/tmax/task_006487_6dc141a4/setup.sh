#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = "/home/user/publications.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE wrote (author_id INTEGER, paper_id INTEGER)")

# Generate sample data
authors = [(i, f"Author {i}") for i in range(1, 51)]
c.executemany("INSERT INTO author VALUES (?, ?)", authors)

wrote_data = []
# Create some predictable co-authorships
# Paper 1: Authors 1, 2, 3
wrote_data.extend([(1, 1), (2, 1), (3, 1)])
# Paper 2: Authors 2, 3
wrote_data.extend([(2, 2), (3, 2)])
# Paper 3: Authors 4, 5
wrote_data.extend([(4, 3), (5, 3)])

# Random data
random.seed(42)
for paper_id in range(4, 101):
    num_authors = random.randint(1, 4)
    paper_authors = random.sample(range(1, 51), num_authors)
    for a in paper_authors:
        wrote_data.append((a, paper_id))

c.executemany("INSERT INTO wrote VALUES (?, ?)", wrote_data)
conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
