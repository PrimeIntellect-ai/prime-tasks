#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc
    pip3 install pytest

    mkdir -p /home/user/pipeline_repo/bin
    cd /home/user/pipeline_repo

    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"
    git init

    # Create the Python script
    cat << 'EOF' > aggregator.py
import sys
import json

counts = {}
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split('|')
    # BUG: Fails when parts length is not exactly 3
    level, date, msg = parts 
    counts[level] = counts.get(level, 0) + 1

print(json.dumps(counts))
EOF

    # Create C decoder source
    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char* auth = getenv("DECODER_SECRET_AUTH");
    if (!auth || strcmp(auth, "9482f8a1b3") != 0) {
        fprintf(stderr, "Error: missing or invalid auth.\n");
        return 1;
    }
    printf("INFO|2023-10-01|User login\n");
    printf("ERROR|2023-10-01|Timeout on port 80\n");
    printf("CRITICAL|2023-10-01|Process Crash|Segfault|DumpCore\n");
    printf("INFO|2023-10-01|User logout\n");
    return 0;
}
EOF

    gcc decoder.c -o bin/decoder
    rm decoder.c

    # Git history construction
    git add aggregator.py bin/decoder
    git commit -m "Initial commit: added aggregator and binary"

    # Commit the secret
    echo "API_KEY=9482f8a1b3" > config.ini
    git add config.ini
    git commit -m "Add config with API key"

    # Remove the secret
    rm config.ini
    git rm config.ini
    git commit -m "Remove config.ini for security"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline_repo
    chmod -R 777 /home/user
