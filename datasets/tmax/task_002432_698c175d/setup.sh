#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest networkx

    # Install sqlite-utils dependencies
    pip3 install click click-default-group sqlite-fts4 tabulate python-dateutil

    # Vendor sqlite-utils
    mkdir -p /app
    cd /app
    wget https://files.pythonhosted.org/packages/source/s/sqlite-utils/sqlite-utils-3.35.1.tar.gz
    tar -xzf sqlite-utils-3.35.1.tar.gz
    mv sqlite-utils-3.35.1 sqlite-utils
    rm sqlite-utils-3.35.1.tar.gz

    # Patch sqlite-utils
    cat << 'EOF' > patch.py
with open("/app/sqlite-utils/sqlite_utils/db.py", "r") as f:
    lines = f.readlines()

in_create_index = False
for i, line in enumerate(lines):
    if "def create_index(" in line:
        in_create_index = True
    elif in_create_index and line.startswith("    def "):
        in_create_index = False

    if in_create_index and "self.execute(sql)" in line:
        lines[i] = line.replace("self.execute(sql)", "pass")

with open("/app/sqlite-utils/sqlite_utils/db.py", "w") as f:
    f.writelines(lines)
EOF
    python3 patch.py
    rm patch.py

    # Set up user and home directory
    useradd -m -s /bin/bash user || true

    # Create db_setup.py
    cat << 'EOF' > /home/user/db_setup.py
import sys
sys.path.insert(0, "/app/sqlite-utils")
import sqlite_utils
import random
import json
import os

def main():
    db_path = "/home/user/graph.db"
    if os.path.exists(db_path):
        os.remove(db_path)
    db = sqlite_utils.Database(db_path)
    db["nodes"].insert_all([{"id": i} for i in range(1, 10001)], pk="id")

    edges = []
    random.seed(42)
    for i in range(50000):
        u = random.randint(1, 10000)
        v = random.randint(1, 10000)
        w = random.randint(1, 100)
        edges.append({"source": u, "target": v, "weight": w})

    db["edges"].insert_all(edges)
    db["edges"].create_index(["source"])
    db["edges"].create_index(["target"])

    pairs = []
    for _ in range(50):
        u = random.randint(1, 10000)
        v = random.randint(1, 10000)
        pairs.append([u, v])
    with open("/home/user/pairs.json", "w") as f:
        json.dump(pairs, f)

if __name__ == "__main__":
    main()
EOF

    # Run db_setup.py to generate the initial database and pairs.json
    cd /home/user
    PYTHONPATH=/app/sqlite-utils python3 db_setup.py

    # Set up environment for user
    echo 'export PYTHONPATH="/app/sqlite-utils:$PYTHONPATH"' >> /home/user/.bashrc

    chmod -R 777 /home/user
