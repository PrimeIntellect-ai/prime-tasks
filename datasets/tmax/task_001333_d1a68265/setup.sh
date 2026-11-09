#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gzip coreutils libc6-dev libc-bin
    pip3 install pytest

    mkdir -p /home/user/old_logs

    cat << 'EOF' > /tmp/log1.txt
[INFO] Starting server
[DEBUG] Checking memory limits
[ERROR] Falla crítica en la conexión
[DEBUG] Retrying connection
[INFO] Shutting down
EOF

    cat << 'EOF' > /tmp/log2.txt
[DEBUG] Initializing cache
[INFO] Cache initialized
[ERROR] Autenticación fallida para el usuario
[DEBUG] User profile loaded
EOF

    iconv -f UTF-8 -t ISO-8859-1 /tmp/log1.txt | gzip > /home/user/old_logs/server1.log.gz
    iconv -f UTF-8 -t ISO-8859-1 /tmp/log2.txt | gzip > /home/user/old_logs/server2.log.gz
    rm /tmp/log1.txt /tmp/log2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
