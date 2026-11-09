#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_notes/

    cat << 'EOF' > /home/user/raw_notes/note1.txt
Title: Initial Setup
Date: 2023-10-01
Body:
Set up the core repository.
Added initial README.
===END===
Title: Database Migration
Date: 2023-10-05
Body:
Migrated the users table to PostgreSQL.
Updated the connection strings.
===END===
EOF

    cat << 'EOF' > /home/user/raw_notes/note2.txt
Title: API v2 Deployment
Date: 2023-10-04
Body:
Deployed the new v2 endpoints to production.
No downtime observed.
===END===
EOF

    chmod -R 777 /home/user
