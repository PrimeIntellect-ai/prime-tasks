#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest requests

    mkdir -p /home/user/math_api
    cd /home/user/math_api

    sqlite3 legacy.db <<EOF
CREATE TABLE old_formulas (id INTEGER PRIMARY KEY, title TEXT, math_string TEXT);
INSERT INTO old_formulas (title, math_string) VALUES ('gravity', '9.81 * m');
INSERT INTO old_formulas (title, math_string) VALUES ('kinetic_energy', '0.5 * m * v**2');
INSERT INTO old_formulas (title, math_string) VALUES ('compound_interest', 'p * (1 + r/n)**(n*t)');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
