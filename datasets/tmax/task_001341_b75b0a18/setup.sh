#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg procps time
    pip3 install pytest pymongo

    # Install MongoDB 6.0
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update && apt-get install -y mongodb-org

    # Install Rust
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R a+w /usr/local/cargo /usr/local/rustup
    export PATH="/usr/local/cargo/bin:$PATH"

    mkdir -p /app/logs
    mkdir -p /data/db

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
mkdir -p /data/db
mongod --fork --logpath /var/log/mongodb.log --bind_ip 127.0.0.1
cd /app/logs && python3.10 -m http.server 8080 &
sleep 2
python3.10 /app/seed_mongo.py
EOF
    chmod +x /app/start_services.sh

    # Create seed_mongo.py
    cat << 'EOF' > /app/seed_mongo.py
#!/usr/bin/env python3
import pymongo
client = pymongo.MongoClient("mongodb://127.0.0.1:27017/")
db = client.backups
# Seed logic would go here
EOF
    chmod +x /app/seed_mongo.py

    # Wrapper for python3 to start services automatically when pytest runs
    rm -f /usr/bin/python3
    cat << 'EOF' > /usr/bin/python3
#!/bin/bash
if ! pgrep -x "mongod" > /dev/null; then
    /app/start_services.sh
fi
exec /usr/bin/python3.10 "$@"
EOF
    chmod +x /usr/bin/python3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
