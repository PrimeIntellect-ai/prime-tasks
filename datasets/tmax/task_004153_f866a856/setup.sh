#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make inotify-tools wget tar
    pip3 install pytest

    # Set up directories
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean
    mkdir -p /var/spool/incoming_logs
    mkdir -p /var/log/sanitized_logs
    chmod 777 /var/spool/incoming_logs /var/log/sanitized_logs

    # Download and vendor cJSON 1.7.15
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz
    mv cJSON-1.7.15 /app/cJSON
    rm v1.7.15.tar.gz

    # Perturb the Makefile
    sed -i 's/^CC\s*=.*/CC = x86_64-linux-gnu-gcc-999/' /app/cJSON/Makefile
    if ! grep -q "x86_64-linux-gnu-gcc-999" /app/cJSON/Makefile; then
        sed -i '1i CC = x86_64-linux-gnu-gcc-999' /app/cJSON/Makefile
    fi

    # Create dummy corpora
    cat << 'EOF' > /app/corpora/evil/log1.jsonl
{"level": "error", "message": "crash", "core_dump": "hexdata..."}
{"level": "fatal", "core_dump": "morehex..."}
EOF

    cat << 'EOF' > /app/corpora/clean/log1.jsonl
{"level": "info", "message": "started"}
{"level": "warn", "message": "high memory"}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
