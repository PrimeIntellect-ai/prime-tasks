#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_configs/dir1/subdir
    mkdir -p /home/user/system_configs/dir2
    mkdir -p /home/user/system_configs/dir3

    cat << 'EOF' > /home/user/system_configs/dir1/confA.ini
[Metadata]
version = 1
track_changes = true

[Settings]
host = localhost
port = 8080
debug = false
EOF

    cat << 'EOF' > /home/user/system_configs/dir2/confB.ini
[Metadata]
version = 3
track_changes = true

[Settings]
port = 9090
timeout = 30
EOF

    cat << 'EOF' > /home/user/system_configs/dir1/subdir/confC.ini
[Metadata]
version = 5
track_changes = false

[Settings]
host = production.local
workers = 8
EOF

    cat << 'EOF' > /home/user/system_configs/dir3/confD.ini
[Metadata]
version = 2
track_changes = true

[Settings]
host = 127.0.0.1
retry = 5
mode = silent
EOF

    chmod -R 777 /home/user
