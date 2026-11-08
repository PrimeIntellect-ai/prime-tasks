#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/network.db <<EOF
CREATE TABLE connections (source INT, target INT);
INSERT INTO connections (source, target) VALUES 
(1, 2), (1, 3), (1, 10),
(2, 4),
(3, 4), (3, 5),
(4, 6),
(5, 7),
(6, 4),
(7, 8), (7, 9),
(8, 11),
(12, 1),
(13, 14);
EOF

    chmod -R 777 /home/user
