#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backup_graph.db <<EOF
CREATE TABLE servers (
    id INTEGER PRIMARY KEY,
    hostname TEXT NOT NULL
);

CREATE TABLE dependencies (
    server_id INTEGER,
    depends_on_id INTEGER,
    FOREIGN KEY(server_id) REFERENCES servers(id),
    FOREIGN KEY(depends_on_id) REFERENCES servers(id)
);

CREATE TABLE stale_routes_cache (
    server_id INTEGER,
    route_path TEXT
);

INSERT INTO servers (id, hostname) VALUES
(1, 'storage-array'),
(2, 'db-primary'),
(3, 'db-replica'),
(4, 'cache-node'),
(5, 'app-server-1'),
(6, 'app-server-2'),
(7, 'load-balancer');

INSERT INTO dependencies (server_id, depends_on_id) VALUES (2, 1);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (3, 2);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (4, 2);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (5, 3);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (5, 4);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (6, 3);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (6, 4);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (7, 5);
INSERT INTO dependencies (server_id, depends_on_id) VALUES (7, 6);

INSERT INTO stale_routes_cache VALUES (1, '1->2->1');
EOF

    chmod -R 777 /home/user
