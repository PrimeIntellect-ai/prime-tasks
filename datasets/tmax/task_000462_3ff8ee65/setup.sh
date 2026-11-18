#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest setuptools

    # Create the mock taxonomy db
    mkdir -p /home/user
    sqlite3 /home/user/taxonomy.db <<EOF
CREATE TABLE taxa (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER);
CREATE INDEX idx_parent_stale ON taxa(parent_id);
-- Deliberately corrupt the index by modifying sqlite_master so any use of it fails or returns wrong data
PRAGMA writable_schema = 1;
UPDATE sqlite_master SET sql = 'CREATE INDEX idx_parent_stale ON taxa(name)' WHERE name = 'idx_parent_stale';
PRAGMA writable_schema = 0;

-- Insert hierarchical data
INSERT INTO taxa VALUES (1, 'Root', NULL);
INSERT INTO taxa VALUES (2, 'Branch_A', 1);
INSERT INTO taxa VALUES (3, 'Branch_B', 1);
INSERT INTO taxa VALUES (4, 'Leaf_A1', 2);
INSERT INTO taxa VALUES (5, 'Leaf_A2', 2);
INSERT INTO taxa VALUES (6, 'Leaf_B1', 3);
-- Add a few hundred more nodes for fuzzing
WITH RECURSIVE
  cnt(x) AS (
     SELECT 7
     UNION ALL
     SELECT x+1 FROM cnt
      LIMIT 494
  )
INSERT INTO taxa (id, name, parent_id)
SELECT x, 'Node_' || x, (x % 50) + 1 FROM cnt;
EOF

    # Create the vendored package
    mkdir -p /app/sqlite-graph-builder-0.4.5/sqlite_graph_builder
    cat << 'EOF' > /app/sqlite-graph-builder-0.4.5/setup.py
from setuptools import setup, find_packages
setup(name='sqlite-graph-builder', version='0.4.5', packages=find_packages())
EOF

    cat << 'EOF' > /app/sqlite-graph-builder-0.4.5/sqlite_graph_builder/__init__.py
from .core import fetch_hierarchy
EOF

    cat << 'EOF' > /app/sqlite-graph-builder-0.4.5/sqlite_graph_builder/core.py
import sqlite3

def fetch_hierarchy(db_path, root_id):
    conn = sqlite3.connect(db_path)
    # PERTURBATION: hardcoded bad index
    cursor = conn.execute("WITH RECURSIVE lineage AS ( "
                          "SELECT id, name, parent_id FROM taxa INDEXED BY idx_parent_stale WHERE id = ? "
                          "UNION ALL "
                          "SELECT t.id, t.name, t.parent_id FROM taxa t INDEXED BY idx_parent_stale "
                          "JOIN lineage l ON t.parent_id = l.id) "
                          "SELECT id, name, parent_id FROM lineage", (root_id,))
    rows = cursor.fetchall()
    conn.close()
    return rows
EOF
    pip3 install -e /app/sqlite-graph-builder-0.4.5

    # Create the Oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/fetch_subtree_oracle.py
import sys
import sqlite3
import json

def build_tree(rows, parent_id):
    children = []
    for row in rows:
        if row[2] == parent_id:
            child = {
                "id": row[0],
                "name": row[1],
                "children": build_tree(rows, row[0])
            }
            children.append(child)
    return sorted(children, key=lambda x: x["id"])

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    root_id = int(sys.argv[1])
    conn = sqlite3.connect('/home/user/taxonomy.db')
    cursor = conn.execute("WITH RECURSIVE lineage AS ( "
                          "SELECT id, name, parent_id FROM taxa WHERE id = ? "
                          "UNION ALL "
                          "SELECT t.id, t.name, t.parent_id FROM taxa t "
                          "JOIN lineage l ON t.parent_id = l.id) "
                          "SELECT id, name, parent_id FROM lineage", (root_id,))
    rows = cursor.fetchall()
    if not rows:
        print(json.dumps({}))
        return

    # Root node is the one matching root_id
    root_row = next((r for r in rows if r[0] == root_id), None)
    if not root_row:
        return

    tree = {
        "id": root_row[0],
        "name": root_row[1],
        "children": build_tree(rows, root_row[0])
    }
    print(json.dumps(tree, separators=(',', ':')))

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/fetch_subtree_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
