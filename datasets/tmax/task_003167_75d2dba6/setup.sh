#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    # 1. Setup SQLite DB
    sqlite3 /home/user/data/users.sqlite <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT, status TEXT);
INSERT INTO users VALUES (1, 'Alice', 'HR', 'active');
INSERT INTO users VALUES (2, 'Bob', 'Engineering', 'active');
INSERT INTO users VALUES (3, 'Charlie', 'Engineering', 'inactive');
INSERT INTO users VALUES (4, 'Diana', 'Marketing', 'active');
EOF

    # 2. Setup JSONL docs
    cat <<EOF > /home/user/data/docs.jsonl
{"doc_id": "d1", "size_bytes": 1024, "type": "pdf"}
{"doc_id": "d2", "size_bytes": 2048, "type": "docx"}
{"doc_id": "d3", "size_bytes": 5000, "type": "png"}
{"doc_id": "d4", "size_bytes": 512, "type": "txt"}
{"doc_id": "d5", "size_bytes": 10000, "type": "mp4"}
{"doc_id": "d6", "size_bytes": 300, "type": "txt"}
EOF

    # 3. Setup CSV Edges
    cat <<EOF > /home/user/data/access.csv
1,d1
1,d2
2,d3
2,d4
3,d5
1,d6
EOF

    chmod -R 777 /home/user
