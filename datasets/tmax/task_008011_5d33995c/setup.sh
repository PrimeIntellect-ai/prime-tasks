#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE vertex (
    v_id INTEGER PRIMARY KEY,
    attributes TEXT
);

CREATE TABLE link (
    src INTEGER,
    dst INTEGER,
    relation_name TEXT,
    FOREIGN KEY(src) REFERENCES vertex(v_id),
    FOREIGN KEY(dst) REFERENCES vertex(v_id)
);

INSERT INTO vertex (v_id, attributes) VALUES
(10, '{"name": "Alice", "role": "admin"}'),
(20, '{"name": "Bob", "role": "user"}'),
(30, '{"name": "Charlie", "role": "user"}'),
(40, '{"name": "David", "role": "guest"}');

INSERT INTO link (src, dst, relation_name) VALUES
(10, 20, "MANAGES"),
(20, 30, "KNOWS"),
(30, 10, "REPORTS_TO"),
(10, 40, "INVITED"),
(40, 20, "KNOWS");
EOF

    sqlite3 /home/user/graph.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chown -R user:user /home/user
    chmod -R 777 /home/user
