#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest fastapi uvicorn

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/vendor/db-backup-api
    mkdir -p /home/user/data

    # Create launch.sh
    cat << 'EOF' > /app/vendor/db-backup-api/launch.sh
#!/bin/bash
uvcorn api:app --host 127.0.0.1 --port 8080
EOF
    chmod +x /app/vendor/db-backup-api/launch.sh

    # Create config.py
    cat << 'EOF' > /app/vendor/db-backup-api/config.py
METADATA_PATH = "/invalid/path/backup_metadata.json"
GRAPH_PATH = "/invalid/path/db_dependencies.json"
EOF

    # Create api.py
    cat << 'EOF' > /app/vendor/db-backup-api/api.py
from fastapi import FastAPI
import json
import config

app = FastAPI()

@app.get("/prioritize-backups")
def prioritize_backups():
    # TODO: Implement backup prioritization
    raise NotImplementedError("Endpoint not implemented")
EOF

    # Create db_dependencies.json
    cat << 'EOF' > /home/user/data/db_dependencies.json
[
  {"source": "db_auth", "target": "db_users"},
  {"source": "db_billing", "target": "db_users"},
  {"source": "db_orders", "target": "db_billing"},
  {"source": "db_orders", "target": "db_users"},
  {"source": "db_orders", "target": "db_catalog"},
  {"source": "db_catalog", "target": "db_users"},
  {"source": "db_logs", "target": "db_users"}
]
EOF

    # Create backup_metadata.json
    cat << 'EOF' > /home/user/data/backup_metadata.json
[
  {"db_name": "db_users", "size_gb": 100, "tier": 1},
  {"db_name": "db_billing", "size_gb": 50, "tier": 1},
  {"db_name": "db_catalog", "size_gb": 20, "tier": 2},
  {"db_name": "db_orders", "size_gb": 200, "tier": 1},
  {"db_name": "db_auth", "size_gb": 8, "tier": 1},
  {"db_name": "db_logs", "size_gb": 500, "tier": 3}
]
EOF

    # Fix permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
