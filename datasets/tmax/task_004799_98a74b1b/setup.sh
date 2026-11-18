#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE sys_nodes (
    node_id INTEGER PRIMARY KEY,
    identifier TEXT NOT NULL
);

CREATE TABLE sys_edges (
    src_id INTEGER,
    dst_id INTEGER,
    rel_type TEXT,
    FOREIGN KEY(src_id) REFERENCES sys_nodes(node_id),
    FOREIGN KEY(dst_id) REFERENCES sys_nodes(node_id)
);

INSERT INTO sys_nodes (node_id, identifier) VALUES
(1, 'AuthService'),
(2, 'PaymentGateway'),
(3, 'UserService'),
(4, 'InventorySystem'),
(5, 'EmailProvider'),
(6, 'AnalyticsEngine');

INSERT INTO sys_edges (src_id, dst_id, rel_type) VALUES
(2, 1, 'DEPENDS_ON'),
(2, 3, 'DEPENDS_ON'),
(3, 1, 'DEPENDS_ON'),
(4, 1, 'DEPENDS_ON'),
(4, 2, 'DEPENDS_ON'),
(4, 3, 'DEPENDS_ON'),
(5, 1, 'DEPENDS_ON'),
(5, 3, 'DEPENDS_ON'),
(6, 1, 'DEPENDS_ON'),
(6, 2, 'DEPENDS_ON'),
(6, 3, 'DEPENDS_ON'),
(6, 4, 'DEPENDS_ON'),
(6, 5, 'DEPENDS_ON');

INSERT INTO sys_edges (src_id, dst_id, rel_type) VALUES
(1, 6, 'LOGS_TO'),
(2, 6, 'LOGS_TO'),
(3, 6, 'LOGS_TO'),
(4, 6, 'LOGS_TO'),
(5, 6, 'LOGS_TO');
EOF

    sqlite3 /home/user/system_graph.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chmod -R 777 /home/user
