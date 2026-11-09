#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

sqlite3 graph.db <<EOF
CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE edges (
    source INTEGER,
    target INTEGER,
    FOREIGN KEY(source) REFERENCES nodes(id),
    FOREIGN KEY(target) REFERENCES nodes(id)
);

INSERT INTO nodes (id, name) VALUES 
(1, 'Alice'),
(2, 'Bob'),
(3, 'Charlie'),
(4, 'David'),
(5, 'Eve'),
(6, 'Frank'),
(7, 'Grace');

-- Alice's friends: Bob, Charlie
INSERT INTO edges (source, target) VALUES (1, 2), (1, 3);
-- Bob's friends: David, Eve
INSERT INTO edges (source, target) VALUES (2, 4), (2, 5);
-- Charlie's friends: Eve, Frank, Alice (cycle)
INSERT INTO edges (source, target) VALUES (3, 5), (3, 6), (3, 1);
-- David's friends: Grace
INSERT INTO edges (source, target) VALUES (4, 7);
EOF

cat << 'EOF' > /home/user/get_2nd_degree.py
import sqlite3
import sys

def get_2nd_degree_friends(db_path, user_id):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # BROKEN QUERY WITH IMPLICIT CROSS JOIN
    query = """
    SELECT n3.name 
    FROM nodes n1, nodes n2, nodes n3, edges e1, edges e2
    WHERE n1.id = ?
    """

    c.execute(query, (user_id,))
    results = c.fetchall()

    # Print results sorted
    names = sorted(list(set([r[0] for r in results])))
    for name in names:
        print(name)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python get_2nd_degree.py <db_path> <user_id>")
        sys.exit(1)
    get_2nd_degree_friends(sys.argv[1], int(sys.argv[2]))
EOF

chmod +x /home/user/get_2nd_degree.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
