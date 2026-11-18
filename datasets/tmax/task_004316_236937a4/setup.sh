#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 build-essential python3-dev
    pip3 install pytest cython

    # Create directories
    mkdir -p /home/user/qa_env/db
    mkdir -p /home/user/qa_env/src
    mkdir -p /home/user/qa_env/results

    # Create legacy DB
    sqlite3 /home/user/qa_env/db/users_v1.db <<EOF
CREATE TABLE old_users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);
INSERT INTO old_users (username, password) VALUES ('admin', 'supersecret123');
INSERT INTO old_users (username, password) VALUES ('jdoe', 'password1!');
INSERT INTO old_users (username, password) VALUES ('alice', 'wonderland');
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
