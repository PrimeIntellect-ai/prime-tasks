#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/network.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER, timestamp INTEGER);

INSERT INTO nodes VALUES (1, 'A', 'North'), (2, 'B', 'North'), (3, 'C', 'North'), (4, 'D', 'North'), (5, 'E', 'North'), (6, 'F', 'South');

-- 1 to 5 path: 1-2-5 (length 2)
-- 3 is heavily connected: 3-1, 3-2, 3-4, 3-5 (Degree 4)
INSERT INTO edges VALUES 
(1, 2, 10, 1000),
(1, 2, 15, 2000), -- Latest 1->2
(2, 5, 20, 1500), -- Latest 2->5
(3, 1, 5, 1000),
(3, 2, 5, 1000),
(3, 4, 5, 1000),
(3, 5, 5, 1000),
(1, 6, 10, 3000); -- Cross region, should be excluded
EOF

    cat << 'EOF' > /home/user/bad_query.sql
SELECT e.source, e.target, e.weight, MAX(e.timestamp), n1.region 
FROM edges e, nodes n1, nodes n2 
WHERE n1.region = n2.region 
GROUP BY e.source, e.target;
EOF

    chmod -R 777 /home/user
