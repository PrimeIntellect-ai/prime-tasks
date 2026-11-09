#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip postgresql redis-server
    pip3 install pytest psycopg2-binary redis

    mkdir -p /app

    cat << 'EOF' > /app/oracle_extractor.py
#!/usr/bin/env python3
import sys
print("[]")
EOF
    chmod +x /app/oracle_extractor.py

    cat << 'EOF' > /app/init_db.sh
#!/bin/bash
# Initialize DB
EOF
    chmod +x /app/init_db.sh

    # Create a wrapper for pytest to start services before running tests
    PYTEST_BIN=$(which pytest)
    mv $PYTEST_BIN ${PYTEST_BIN}_real
    cat << EOF > $PYTEST_BIN
#!/bin/bash
service postgresql start
service redis-server start
sleep 2
exec ${PYTEST_BIN}_real "\$@"
EOF
    chmod +x $PYTEST_BIN

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
