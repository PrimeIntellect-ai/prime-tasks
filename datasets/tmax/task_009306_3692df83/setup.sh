#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/artifacts.db "CREATE TABLE packages (id INTEGER PRIMARY KEY, name TEXT, version TEXT, path TEXT, active INTEGER);"
    sqlite3 /home/user/artifacts.db "INSERT INTO packages (name, version, path, active) VALUES ('BaseLib', '1.0', '/repo/baselib/1.0', 1);"
    sqlite3 /home/user/artifacts.db "INSERT INTO packages (name, version, path, active) VALUES ('OldTool', '0.9', '/repo/oldtool/0.9', 1);"

    cat << 'EOF' > /home/user/incoming_artifacts.json
[
  {
    "name": "DataPipeline",
    "version": "2.0",
    "path": "/repo/dp/2.0",
    "checksum": "sha-abc",
    "dependencies": ["BaseLib", "DataParser"]
  },
  {
    "name": "DataParser",
    "version": "1.5",
    "path": "/repo/dp/1.5",
    "checksum": "sha-def",
    "dependencies": ["BaseLib", "MathLib"]
  },
  {
    "name": "BaseLib",
    "version": "1.1",
    "path": "/repo/baselib/1.1",
    "checksum": "sha-ghi",
    "dependencies": []
  },
  {
    "name": "MathLib",
    "version": "3.0",
    "path": "/repo/math/3.0",
    "checksum": "sha-jkl",
    "dependencies": []
  },
  {
    "name": "UnusedLib",
    "version": "1.0",
    "path": "/repo/unused/1.0",
    "checksum": "sha-mno",
    "dependencies": []
  }
]
EOF

    chmod -R 777 /home/user
