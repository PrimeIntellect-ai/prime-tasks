#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /tmp/archive_build/etc
    mkdir -p /tmp/archive_build/data
    mkdir -p /tmp/archive_build/bin

    cat << 'EOF' > /tmp/archive_build/etc/app.conf
listen_port=80
db_path=/var/lib/db/prod.sqlite
max_connections=100
EOF

    touch /tmp/archive_build/data/db.sqlite

    cat << 'EOF' > /tmp/archive_build/bin/app_mock
#!/bin/bash
CONFIG=$1
if [ -z "$CONFIG" ]; then exit 1; fi
PORT=$(grep listen_port "$CONFIG" | cut -d= -f2)
DB=$(grep db_path "$CONFIG" | cut -d= -f2)
echo "App running. Port: $PORT, DB: $DB" > /home/user/staging/app.log
while true; do sleep 60; done
EOF

    chmod +x /tmp/archive_build/bin/app_mock

    tar -czf /home/user/backups/archive.tar.gz -C /tmp/archive_build .
    rm -rf /tmp/archive_build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
