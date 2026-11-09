#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/configs.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE server_configs (id INTEGER PRIMARY KEY, hostname TEXT, config_text TEXT)")

# Host A: 3 configs, all normalize to the same result
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('web-01', 'listen 80\n# default port\n server_name example.com ')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('web-01', '\nlisten 80\nserver_name example.com\n\n')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('web-01', '  listen 80  \n  # added comment  \nserver_name example.com')")

# Host B: 2 configs, normalize to 2 different results
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('db-01', 'max_connections 100\n# tuning')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('db-01', 'max_connections 200\n# tuning increased')")

# Host C: 5 configs, normalize to 3 different results
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('cache-01', 'memory 1G\nport 11211')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('cache-01', 'memory 1G\n# test\nport 11211')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('cache-01', 'memory 2G\nport 11211')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('cache-01', 'memory 2G\n\nport 11211\n')")
c.execute("INSERT INTO server_configs (hostname, config_text) VALUES ('cache-01', 'memory 4G\nport 11211')")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
