#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat sqlite3
    pip3 install pytest

    mkdir -p /app/bash-sqlite-graph-api
    mkdir -p /app/data

    cat << 'EOF' > /app/bash-sqlite-graph-api/run_api.sh
#!/bin/bash
# Starts the graph traversal API
socat TCP4-LISTEN:8888 EXEC:./handler.sh
EOF
    chmod +x /app/bash-sqlite-graph-api/run_api.sh

    cat << 'EOF' > /app/bash-sqlite-graph-api/handler.sh
#!/bin/bash
read NODE_ID
NODE_ID=$(echo "$NODE_ID" | tr -d '\r\n')
sqlite3 /app/data/graph.db "
WITH RECURSIVE descendants AS (
    SELECT child_id FROM edges WHERE parent_id = $NODE_ID
    UNION ALL
    SELECT e.child_id FROM edges e
    INNER JOIN descendants d ON e.parent_id = d.child_id
)
SELECT COUNT(*) FROM descendants;
"
EOF
    chmod +x /app/bash-sqlite-graph-api/handler.sh

    sqlite3 /app/data/graph.db << 'EOF'
CREATE TABLE edges (parent_id INTEGER, child_id INTEGER);
-- Insert dummy graph data
INSERT INTO edges (parent_id, child_id) VALUES (1, 2), (1, 3), (2, 4), (2, 5), (3, 6), (5, 7), (5, 8);
-- For the sake of the test, add noise
INSERT INTO edges (parent_id, child_id) SELECT parent_id+10, child_id+10 FROM edges;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
