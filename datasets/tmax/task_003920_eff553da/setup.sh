#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gcc make
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://github.com/troydhanson/uthash/archive/refs/tags/v2.3.0.tar.gz
    tar -xzf v2.3.0.tar.gz
    rm v2.3.0.tar.gz

    # Perturb uthash.h
    sed -i 's/HASH_ADD_STR/HASH_ADD_STTR/g' /app/uthash-2.3.0/src/uthash.h

    # Create oracle
    cat << 'EOF' > /app/oracle_dedup
#!/usr/bin/env python3
import sys
import re
from datetime import datetime, timezone

seen = set()

for line in sys.stdin:
    line = line.strip('\n')
    if not line:
        continue
    parts = line.split('|', 1)
    if len(parts) != 2:
        continue
    ts_str, raw_payload = parts

    try:
        dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        dt = dt.replace(tzinfo=timezone.utc)
        epoch = int(dt.timestamp())
    except ValueError:
        continue

    norm = raw_payload.lower()
    norm = re.sub(r'[^a-z0-9]', ' ', norm)
    norm = ' '.join(norm.split())

    if norm not in seen:
        seen.add(norm)
        print(f"{epoch}|{norm}")
EOF
    chmod +x /app/oracle_dedup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
