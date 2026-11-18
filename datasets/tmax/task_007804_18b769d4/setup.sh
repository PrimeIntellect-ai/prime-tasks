#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deps.json
{
  "frontend": ["api", "utils"],
  "api": ["database", "auth"],
  "auth": ["utils", "database"],
  "database": ["core"],
  "utils": ["core"],
  "core": []
}
EOF

    sqlite3 /home/user/artifacts.db "CREATE TABLE packages (name TEXT PRIMARY KEY, language TEXT);"
    sqlite3 /home/user/artifacts.db "INSERT INTO packages (name, language) VALUES ('frontend', 'javascript'), ('api', 'go'), ('auth', 'python'), ('database', 'c++'), ('utils', 'python'), ('core', 'c');"

    chmod -R 777 /home/user
