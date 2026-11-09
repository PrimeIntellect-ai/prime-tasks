#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gcc make zlib1g-dev coreutils
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # 1. Vendor pigz
    mkdir -p /app
    cd /app
    wget https://zlib.net/pigz/pigz-2.8.tar.gz
    tar -xzf pigz-2.8.tar.gz
    rm pigz-2.8.tar.gz
    cd pigz-2.8
    sed -i 's/^CC=.*/CC=false/' Makefile
    chown -R user:user /app/pigz-2.8

    # 2. Create archiver.conf
    cat << 'EOF' > /home/user/archiver.conf
# Archiver configuration
LOG_DIR=/home/user/wal_logs
MAX_THREADS=4
EOF

    # 3. Create WAL Logs
    mkdir -p /home/user/wal_logs
    cd /home/user/wal_logs

    # Create valid highly-compressible WAL files
    for i in $(seq 1 20); do
        fname=$(printf "wal_%03d.log" $i)
        printf "WAL_" > "$fname"
        yes "DATA_RECORD_$(printf '%04d' $i)" | head -c 1048576 >> "$fname"
    done

    # Create invalid incompressible files (fake WALs)
    for i in $(seq 21 35); do
        fname=$(printf "wal_%03d.log" $i)
        printf "BAD_" > "$fname"
        head -c 1048576 /dev/urandom >> "$fname"
    done

    # Set permissions
    chmod -R 777 /home/user
