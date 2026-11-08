#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = '/home/user/kg.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE triples (subject TEXT, predicate TEXT, object TEXT)')

# Generate dummy data
batch = []
predicates = ['is_a', 'has_skill', 'assigned_to', 'likes', 'knows']
objects = ['AI_Agent', 'Human', 'QueryOptimization', 'Python', 'Project_X', 'Project_Y', 'Data', 'Graphs']

for i in range(100000):
    subj = f"Entity_{random.randint(1, 50000)}"
    pred = random.choice(predicates)
    obj = random.choice(objects)
    batch.append((subj, pred, obj))

c.executemany('INSERT INTO triples VALUES (?, ?, ?)', batch)

# Insert the golden targets
targets = ["AlphaBot", "Zeta_System", "Omni_Agent"]
for t in targets:
    c.execute("INSERT INTO triples VALUES (?, 'is_a', 'AI_Agent')", (t,))
    c.execute("INSERT INTO triples VALUES (?, 'has_skill', 'QueryOptimization')", (t,))
    c.execute("INSERT INTO triples VALUES (?, 'assigned_to', 'Project_X')", (t,))

# Add a false positive missing one predicate
c.execute("INSERT INTO triples VALUES ('Beta_System', 'is_a', 'AI_Agent')")
c.execute("INSERT INTO triples VALUES ('Beta_System', 'has_skill', 'QueryOptimization')")
c.execute("INSERT INTO triples VALUES ('Beta_System', 'assigned_to', 'Project_Y')")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
