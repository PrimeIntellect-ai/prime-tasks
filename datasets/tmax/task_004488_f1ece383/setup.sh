#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/artifacts.db <<EOF
CREATE TABLE v1_artifacts (id INTEGER PRIMARY KEY, webhook_url TEXT);
INSERT INTO v1_artifacts (id, webhook_url) VALUES 
(1, 'http://build.internal/api/v1/artifacts/frontend/v1.0.0?file=bundle.js&encoded_meta=YnJhbmNoPW1haW4sY29tbWl0PWEzZjI5Y2Q%3D'),
(2, 'http://build.internal/api/v1/artifacts/backend/v2.3.1?file=server.bin&encoded_meta=YnJhbmNoPXN0YWdpbmcsY29tbWl0PWI4MzkxMmY%3D'),
(3, 'http://build.internal/api/v1/artifacts/auth-service/v0.9.5?file=auth-linux-amd64&encoded_meta=YnJhbmNoPWhvdGZpeC0xLGNvbW1pdD1jMTIzNDU2');
EOF

    chmod -R 777 /home/user
