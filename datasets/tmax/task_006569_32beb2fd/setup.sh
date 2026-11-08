#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/data

    # Create tracker.ini
    cat << 'EOF' > /home/user/tracker.ini
[Settings]
archive_path = /home/user/archive.dat
EOF

    # Create data files
    cat << 'EOF' > /home/user/data/service1.json
{
    "service": "auth",
    "port": 8080,
    "config_hash": "AAAAABBBCCDDDDD"
}
EOF

    cat << 'EOF' > /home/user/data/database.csv
id,name,hash,status
1,main_db,XXXYYZZZZ,active
EOF

    cat << 'EOF' > /home/user/data/cache.json
{
    "memory": "512M",
    "config_hash": "111122233"
}
EOF

    # Ensure proper permissions
    chmod -R 755 /home/user/data
    chmod 644 /home/user/tracker.ini

    # Ensure /home/user is writable
    chmod -R 777 /home/user
