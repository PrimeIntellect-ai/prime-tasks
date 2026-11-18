#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tmp_setup
    cd /home/user/tmp_setup

    # Node 1 logs
    mkdir -p node1
    cat << 'EOF' | gzip > node1/app_log_01.txt.gz
Info: Starting backup process...
[METADATA-EXPORT] file=/etc/passwd checksum=1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Warning: Low memory.
EOF

    cat << 'EOF' | gzip > node1/app_log_02.txt.gz
Info: Processing secondary volume.
[METADATA-EXPORT] file=/etc/hostname checksum=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
EOF
    tar -czf node1_logs.tar.gz -C node1 .

    # Node 2 logs
    mkdir -p node2
    cat << 'EOF' | gzip > node2/app_log_01.txt.gz
Debug: Initialization complete.
[METADATA-EXPORT] file=/var/www/html/index.html checksum=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
Error: Failed to fetch metadata.
[METADATA-EXPORT] file=/root/.bashrc checksum=cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe
EOF
    tar -czf node2_logs.tar.gz -C node2 .

    # Create outer tar
    tar -cf /home/user/backup_archive.tar node1_logs.tar.gz node2_logs.tar.gz

    # Cleanup
    cd /home/user
    rm -rf /home/user/tmp_setup

    chmod -R 777 /home/user
