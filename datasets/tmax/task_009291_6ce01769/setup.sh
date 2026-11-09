#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/logs /home/user/archive /home/user/keys

    cat << 'EOF' > /home/user/app/logs/access.log
[2023-10-01T12:00:00Z] GET /login?redirect=http://evil.com&password=hunter2&token=abc123xyz HTTP/1.1
[2023-10-01T12:05:00Z] GET /login?redirect=/home&password=secretpass&token=def456uvw HTTP/1.1
[2023-10-01T12:10:00Z] GET /login?token=onlytoken789&password=anotherpwd&redirect=/dashboard HTTP/1.1
EOF

    cat << 'EOF' > /home/user/app/config.env
DB_HOST=localhost
DB_USER=admin
DB_PASSWORD=oldsecretpassword
DB_PORT=5432
EOF

    echo "my-super-secret-backup-key-9988" > /home/user/keys/backup.key

    chmod -R 777 /home/user
